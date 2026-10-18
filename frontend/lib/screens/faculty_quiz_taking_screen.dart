import 'package:flutter/material.dart';
import 'package:stela_app/constants/colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math';
import 'quiz_results_screen.dart';
import '../models/assessment_tagging.dart';
import '../models/quiz_model.dart';
import '../widgets/code_editor_widget.dart';
import '../services/quiz_service.dart';
import '../services/assessment_tagging_service.dart';
import '../services/taxonomy_service.dart';

class FacultyQuizTakingScreen extends StatefulWidget {
  final Map<String, dynamic> quiz;
  final Map<String, dynamic> subject;

  const FacultyQuizTakingScreen({
    Key? key,
    required this.quiz,
    required this.subject,
  }) : super(key: key);

  @override
  _FacultyQuizTakingScreenState createState() =>
      _FacultyQuizTakingScreenState();
}

class _FacultyQuizTakingScreenState extends State<FacultyQuizTakingScreen>
    with WidgetsBindingObserver {
  int currentQuestionIndex = 0;
  Map<int, int> selectedAnswers = {}; // For MCQ questions
  Map<int, String> codingAnswers = {}; // For coding questions
  Map<int, ProgrammingLanguage> codingLanguages =
      {}; // Student-selected coding language
  Map<int, String> subjectiveAnswers = {}; // For subjective questions
  final TextEditingController _subjectiveController = TextEditingController();
  int? _subjectiveControllerIndex;
  List<Map<String, dynamic>> questions = [];
  Map<String, TaxonomyNode> taxonomyNodes = const {};
  Timer? _timer;
  int timeRemaining = 0; // in seconds
  int totalTimeAllocated = 0; // in seconds
  bool quizCompleted = false;
  DateTime? quizStartTime;
  bool _alreadySubmitted = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeQuiz();
  }

  Future<void> _initializeQuiz() async {
    questions = List<Map<String, dynamic>>.from(
      widget.quiz['facultyQuestions'] ?? widget.quiz['questions'] ?? const [],
    );

    final quizId = (widget.quiz['id'] ?? widget.quiz['key'] ?? '').toString();
    if (quizId.isNotEmpty && questions.isNotEmpty) {
      final rawSubjectId = (widget.subject['id'] ??
              widget.subject['value'] ??
              widget.subject['label'] ??
              'general')
          .toString();
      final subjectKey = QuizService.mapSubjectIdToFacultyKey(rawSubjectId);
      try {
        questions = await AssessmentTaggingService.loadQuizQuestionTags(
          subjectKey: subjectKey,
          quizId: quizId,
          questions: questions,
        );
      } catch (error) {
        debugPrint('Assessment tags could not be loaded: $error');
        _showEvidenceLoadNotice(
          'Assessment feedback is unavailable for this quiz right now.',
        );
      }
      try {
        final registry =
            await TaxonomyRegistry.loadFromFirebase(subjectKey: subjectKey);
        taxonomyNodes = registry.nodes;
      } catch (error) {
        debugPrint('Assessment taxonomy could not be loaded: $error');
        _showEvidenceLoadNotice(
          'Concept hierarchy is unavailable; parent roll-ups are omitted.',
        );
      }
    }

    if (!mounted) {
      return;
    }

    // Shuffle questions and options so each user sees a random order
    _shuffleQuestionsAndOptions();

    // Initialize coding defaults
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      if ((q['type'] ?? '').toString() == 'coding') {
        final lang = _getProgrammingLanguage(q['language']?.toString());
        codingLanguages[i] = lang;
      }
    }

    // Parse duration and set timer
    String duration = widget.quiz['duration'] ?? '15 min';
    int minutes = int.tryParse(duration.split(' ')[0]) ?? 15;
    timeRemaining = minutes * 60;
    totalTimeAllocated = minutes * 60;

    // Record start time
    quizStartTime = DateTime.now();

    _startTimer();
    // Check if the current user has already submitted this quiz
    _checkExistingSubmission();
  }

  void _showEvidenceLoadNotice(String message) {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }

  /// Shuffle the questions list and shuffle options within each question.
  /// Uses a time-seeded Random to ensure different users/attempts get different orders.
  void _shuffleQuestionsAndOptions() {
    // Create a deterministic seed per user+quiz so each user gets a unique order
    String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    String quizId = (widget.quiz['id'] ?? widget.quiz['key'] ?? '').toString();

    int baseSeed;
    if (uid.isNotEmpty) {
      baseSeed = _stableSeed(uid + '::' + quizId);
    } else {
      baseSeed = DateTime.now().millisecondsSinceEpoch;
    }

    // Shuffle options for MCQ questions while keeping track of the correct index
    for (int i = 0; i < questions.length; i++) {
      final q = Map<String, dynamic>.from(questions[i]);
      final type = (q['type'] ?? '').toString();

      // Only MCQs and image MCQs have options/correct indexes to shuffle.
      if (type == 'coding' || type == 'subjective') {
        questions[i] = q;
        continue;
      }

      if (type == 'image' &&
          (q['imageAnswerType'] ?? 'subjective').toString() != 'mcq') {
        questions[i] = q;
        continue;
      }

      final List<String> opts = List<String>.from(q['options'] ?? []);
      final int correctIndex = q['correct'] ?? 0;

      // Pair option text with original index
      final List<Map<String, dynamic>> paired = [];
      for (int j = 0; j < opts.length; j++) {
        paired.add({'text': opts[j], 'orig': j});
      }

      // Use question-specific seed so options vary across questions
      final rand = Random(baseSeed + i);
      paired.shuffle(rand);

      // Build new options list and find new correct index
      final List<String> newOptions =
          paired.map((p) => p['text'] as String).toList();
      final int newCorrect =
          paired.indexWhere((p) => p['orig'] == correctIndex);

      q['options'] = newOptions;
      q['correct'] = newCorrect >= 0 ? newCorrect : 0;

      questions[i] = q;
    }

    // Finally, shuffle question order itself using the base seed so it's stable per-user
    questions.shuffle(Random(baseSeed ^ 0x9e3779b1));
  }

  int _stableSeed(String s) {
    // Simple deterministic hash to produce a non-negative int seed
    int h = 0;
    for (int i = 0; i < s.length; i++) {
      h = (h * 31 + s.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }

  List<String> _extractQuestionKeywords(Map<String, dynamic> question) {
    final raw = question['keywords'];
    if (raw is List) {
      return raw
          .map((k) => k.toString().trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList();
    }
    if (raw is String) {
      return raw
          .split(RegExp(r'[,;\n]+'))
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList();
    }
    return <String>[];
  }

  List<String> _matchKeywordsInAnswer(String answer, List<String> keywords) {
    final normalizedAnswer = answer.toLowerCase();
    final matched = <String>[];
    for (final keyword in keywords) {
      final escaped = RegExp.escape(keyword.trim());
      if (escaped.isEmpty) continue;
      final pattern = RegExp(r'(^|[^a-z0-9])' + escaped + r'([^a-z0-9]|$)',
          caseSensitive: false);
      if (pattern.hasMatch(normalizedAnswer)) {
        matched.add(keyword);
      }
    }
    return matched;
  }

  Future<void> _checkExistingSubmission() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final studentId = user?.uid;
      if (studentId == null || studentId.isEmpty) return;
      final quizId = (widget.quiz['id'] ?? widget.quiz['key'] ?? '').toString();
      if (quizId.isEmpty) return;
      final snap = await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .where('quizId', isEqualTo: quizId)
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        setState(() {
          _alreadySubmitted = true;
        });
      }
    } catch (e) {
      print('Error checking existing submission: $e');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (timeRemaining > 0) {
        setState(() {
          timeRemaining--;
        });
      } else {
        _completeQuiz(reason: 'time_up');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (quizCompleted || _isSubmitting || _alreadySubmitted) return;

    final stateName = state.toString().split('.').last;
    final movedAway = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        stateName == 'hidden';

    if (movedAway) {
      _completeQuiz(
        reason: 'focus_lost_$stateName',
        autoTerminated: true,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _subjectiveController.dispose();
    super.dispose();
  }

  void _selectAnswer(int answerIndex) {
    setState(() {
      selectedAnswers[currentQuestionIndex] = answerIndex;
    });
  }

  void _nextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
      _syncSubjectiveControllerIfNeeded();
    } else {
      _completeQuiz(reason: 'completed');
    }
  }

  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      setState(() {
        currentQuestionIndex--;
      });
      _syncSubjectiveControllerIfNeeded();
    }
  }

  void _syncSubjectiveControllerIfNeeded() {
    final q = questions.isNotEmpty ? questions[currentQuestionIndex] : null;
    final type = (q?['type'] ?? '').toString();
    if (type != 'subjective' && type != 'image') return;

    // For image questions, only sync if answer type is subjective
    if (type == 'image' &&
        (q?['imageAnswerType'] ?? 'subjective').toString() != 'subjective')
      return;

    if (_subjectiveControllerIndex == currentQuestionIndex) return;
    _subjectiveControllerIndex = currentQuestionIndex;
    _subjectiveController.text = subjectiveAnswers[currentQuestionIndex] ?? '';
    _subjectiveController.selection = TextSelection.fromPosition(
      TextPosition(offset: _subjectiveController.text.length),
    );
  }

  void _showTestResults() async {
    final q = questions[currentQuestionIndex];
    if (q['testCases'] == null || (q['testCases'] as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No test cases available for this question')),
      );
      return;
    }

    final code = codingAnswers[currentQuestionIndex] ?? "";

    // Show loading state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Running Tests...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );

    final studentLanguage = codingLanguages[currentQuestionIndex] ??
        _getProgrammingLanguage(q['language']?.toString());
    final facultyLanguage = _getProgrammingLanguage(q['language']?.toString());

    // Simulated Code Execution
    final results = await SimulatedCodeRunner.runTests(
      code: code,
      testCasesData: q['testCases'] as List,
      language: studentLanguage,
      solutionLanguage: facultyLanguage,
      solutionCode: q['solutionCode']?.toString(),
    );

    // Dismiss loading and show results
    if (mounted) Navigator.pop(context);

    showDialog(
      context: context,
      builder: (ctx) => TestResultsDialog(
        results: results,
        language: studentLanguage,
      ),
    );
  }

  void _completeQuiz({
    String reason = 'completed',
    bool autoTerminated = false,
  }) {
    if (quizCompleted || _isSubmitting || _alreadySubmitted) return;

    _timer?.cancel();
    setState(() {
      quizCompleted = true;
      _isSubmitting = true;
    });
    _showResults(
      completionReason: reason,
      autoTerminated: autoTerminated,
    );
  }

  Future<void> _showResults({
    required String completionReason,
    required bool autoTerminated,
  }) async {
    // Show loading while calculating
    if (!autoTerminated && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: CircularProgressIndicator()),
      );
    }

    double score = 0;
    double totalMarks = 0;
    double marksFromCorrect = 0;
    double marksFromPartial = 0;
    int codingTestCasesPassed = 0;
    int codingTestCasesTotal = 0;
    final codingTestCasesPassedByQuestion =
        List<int>.filled(questions.length, 0);
    final codingTestCasesTotalByQuestion =
        List<int>.filled(questions.length, 0);
    final subjectiveKeywordScoreByQuestion =
        List<double>.filled(questions.length, 0.0);
    final subjectiveMatchedKeywordsByQuestion =
        List<List<String>>.generate(questions.length, (_) => <String>[]);
    final subjectiveTotalKeywordsByQuestion =
        List<int>.filled(questions.length, 0);
    final earnedMarksByQuestion = List<double>.filled(questions.length, 0);
    final possibleMarksByQuestion = List<double>.filled(questions.length, 0);
    List<int?> userAnswers = [];

    // Calculate results and prepare user answers array
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final type = (q['type'] ?? '').toString();
      final maxMarks = _questionMaxMarks(q);
      totalMarks += maxMarks;
      possibleMarksByQuestion[i] = maxMarks;

      if (type == 'coding') {
        userAnswers.add(null); // MCQs only use this list

        final code = codingAnswers[i] ?? '';
        final testCases = (q['testCases'] ?? []) as List;
        final studentLanguage = codingLanguages[i] ??
            _getProgrammingLanguage(q['language']?.toString());
        final facultyLanguage =
            _getProgrammingLanguage(q['language']?.toString());

        codingTestCasesTotalByQuestion[i] = testCases.length;

        if (code.trim().isNotEmpty && testCases.isNotEmpty) {
          final results = await SimulatedCodeRunner.runTests(
            code: code,
            testCasesData: testCases,
            language: studentLanguage,
            solutionLanguage: facultyLanguage,
            solutionCode: q['solutionCode']?.toString(),
            skipDelay: true,
          );
          int passed = results.where((r) => r.isPassed).length;
          codingTestCasesPassedByQuestion[i] = passed;
          final earned = (passed / testCases.length) * maxMarks;
          score += earned;
          earnedMarksByQuestion[i] = earned;
          codingTestCasesPassed += passed;
          codingTestCasesTotal += testCases.length;

          if (passed == testCases.length) {
            marksFromCorrect += maxMarks;
          } else if (passed > 0) {
            marksFromPartial += earned;
          }
        } else {
          // No code / no test cases: earns 0
          codingTestCasesPassedByQuestion[i] = 0;
          if (testCases.isNotEmpty) codingTestCasesTotal += testCases.length;
        }
      } else if (type == 'subjective') {
        userAnswers.add(null);
        final answerText = (subjectiveAnswers[i] ?? '').trim();
        final keywords = _extractQuestionKeywords(q);
        subjectiveTotalKeywordsByQuestion[i] = keywords.length;

        if (answerText.isNotEmpty && keywords.isNotEmpty) {
          final matched = _matchKeywordsInAnswer(answerText, keywords);
          subjectiveMatchedKeywordsByQuestion[i] = matched;
          final earned = (matched.length / keywords.length) * maxMarks;
          subjectiveKeywordScoreByQuestion[i] = earned;
          earnedMarksByQuestion[i] = earned;
          score += earned;

          if (matched.length == keywords.length) {
            marksFromCorrect += maxMarks;
          } else if (matched.isNotEmpty) {
            marksFromPartial += earned;
          }
        }
      } else if (type == 'image') {
        // Image questions can be MCQ or subjective type
        final imageAnswerType =
            (q['imageAnswerType'] ?? 'subjective').toString();

        if (imageAnswerType == 'mcq') {
          // Treat as MCQ for grading
          int? selectedAnswer = selectedAnswers[i];
          userAnswers.add(selectedAnswer);

          int correctAnswer = q['correct'] ?? 0;
          if (selectedAnswer != null && selectedAnswer == correctAnswer) {
            score += maxMarks;
            earnedMarksByQuestion[i] = maxMarks;
            marksFromCorrect += maxMarks;
          }
        } else {
          // Treat as subjective for grading
          userAnswers.add(null);
          final answerText = (subjectiveAnswers[i] ?? '').trim();
          final keywords = _extractQuestionKeywords(q);
          subjectiveTotalKeywordsByQuestion[i] = keywords.length;

          if (answerText.isNotEmpty && keywords.isNotEmpty) {
            final matched = _matchKeywordsInAnswer(answerText, keywords);
            subjectiveMatchedKeywordsByQuestion[i] = matched;
            final earned = (matched.length / keywords.length) * maxMarks;
            subjectiveKeywordScoreByQuestion[i] = earned;
            earnedMarksByQuestion[i] = earned;
            score += earned;

            if (matched.length == keywords.length) {
              marksFromCorrect += maxMarks;
            } else if (matched.isNotEmpty) {
              marksFromPartial += earned;
            }
          }
        }
      } else {
        int? selectedAnswer = selectedAnswers[i];
        userAnswers.add(selectedAnswer);

        int correctAnswer = q['correct'] ?? 0;
        if (selectedAnswer != null && selectedAnswer == correctAnswer) {
          score += maxMarks;
          earnedMarksByQuestion[i] = maxMarks;
          marksFromCorrect += maxMarks;
        }
      }
    }

    // Dismiss loading
    if (!autoTerminated && mounted) {
      Navigator.pop(context);
    }

    double percentage = (score / (totalMarks > 0 ? totalMarks : 1)) * 100;

    // Calculate time taken
    Duration timeTaken = quizStartTime != null
        ? DateTime.now().difference(quizStartTime!)
        : Duration(seconds: totalTimeAllocated - timeRemaining);

    // Persist submission to Firestore so faculty can view it
    String? submissionDocId;
    // Double-check to prevent multiple submissions (race condition)
    try {
      final user = FirebaseAuth.instance.currentUser;
      final studentId = user?.uid ?? '';
      final quizIdCheck =
          (widget.quiz['id'] ?? widget.quiz['key'] ?? '').toString();
      if (studentId.isNotEmpty && quizIdCheck.isNotEmpty) {
        final existing = await FirebaseFirestore.instance
            .collection('quiz_submissions')
            .where('quizId', isEqualTo: quizIdCheck)
            .where('studentId', isEqualTo: studentId)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          // Already submitted
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'You have already submitted this quiz. Multiple attempts are not allowed.')));
            setState(() {
              _isSubmitting = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      print('Error checking existing submission before save: $e');
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      final studentId = user?.uid ?? '';
      String studentName = '';
      String studentEnrollment = '';
      if (studentId.isNotEmpty) {
        final studentDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .get();
        if (studentDoc.exists) {
          final data = studentDoc.data();
          studentName = data?['name'] ?? '';
          studentEnrollment = (data?['enrollmentNumber'] ??
                  data?['enrollmentNo'] ??
                  data?['enrollment'] ??
                  '')
              .toString();
        }
      }

      // Resolve faculty info: prefer widget.quiz fields but try to lookup in Realtime DB when missing.
      String facultyId = widget.quiz['createdBy'] ?? '';
      String facultyName = widget.quiz['createdByName'] ?? '';

      // Compute a subjectKey that matches the Realtime DB structure used by QuizService.
      final rawSubjectId = (widget.subject['id'] ??
              widget.subject['value'] ??
              widget.subject['label'] ??
              '')
          .toString()
          .toLowerCase();
      final subjectKey = QuizService.mapSubjectIdToFacultyKey(rawSubjectId);

      if (facultyId.isEmpty || facultyName.isEmpty) {
        try {
          // Attempt to find the quiz in Realtime Database under the subjectKey and extract creator metadata.
          print(
              'Debug: attempting RTDB lookup for subjectKey="$subjectKey" (raw="$rawSubjectId")');
          if (subjectKey.isNotEmpty) {
            final dbRef = FirebaseDatabase.instance
                .ref()
                .child('quizzes')
                .child(subjectKey);
            final snap = await dbRef.get();
            print('Debug: RTDB snap.exists=${snap.exists}');
            if (snap.exists) {
              final data = snap.value as Map<dynamic, dynamic>;
              print('Debug: RTDB entries=${data.keys.length}');

              // Helper to compare candidate quiz map with widget.quiz
              bool matchesQuiz(Map<dynamic, dynamic> candidate) {
                try {
                  // Fallback: match by title and duration and number of questions
                  final t1 = (candidate['title'] ?? '').toString();
                  final t2 = (widget.quiz['title'] ?? '').toString();
                  final d1 = (candidate['duration'] ?? '').toString();
                  final d2 = (widget.quiz['duration'] ?? '').toString();
                  final q1 = (candidate['questions'] is List)
                      ? (candidate['questions'] as List).length
                      : 0;
                  final q2 = (widget.quiz['questions'] is List)
                      ? (widget.quiz['questions'] as List).length
                      : 0;
                  return t1 == t2 && d1 == d2 && q1 == q2;
                } catch (e) {
                  return false;
                }
              }

              // Search top-level entries for either unit -> quiz or direct quiz
              bool found = false;
              for (var entry in data.entries) {
                final key = entry.key;
                final value = entry.value;
                if (value is Map) {
                  // If this looks like a unit (contains nested quizzes)
                  bool isUnit = false;
                  value.forEach((subKey, subValue) {
                    if (subValue is Map &&
                        subValue.containsKey('title') &&
                        subValue.containsKey('questions')) {
                      isUnit = true;
                    }
                  });

                  if (isUnit) {
                    // iterate nested quizzes
                    value.forEach((subKey, subValue) {
                      if (!found && subValue is Map) {
                        // If widget.quiz has a key, try to match by it
                        if (widget.quiz.containsKey('key') &&
                            widget.quiz['key'] != null &&
                            widget.quiz['key'].toString().isNotEmpty) {
                          if (widget.quiz['key'].toString() ==
                              subKey.toString()) {
                            facultyId =
                                subValue['createdBy']?.toString() ?? facultyId;
                            facultyName =
                                subValue['createdByName']?.toString() ??
                                    facultyName;
                            found = true;
                          }
                        } else if (matchesQuiz(subValue)) {
                          facultyId =
                              subValue['createdBy']?.toString() ?? facultyId;
                          facultyName = subValue['createdByName']?.toString() ??
                              facultyName;
                          found = true;
                        }
                      }
                    });
                  } else {
                    // direct quiz
                    if (!found &&
                        value.containsKey('title') &&
                        value.containsKey('questions')) {
                      if (widget.quiz.containsKey('key') &&
                          widget.quiz['key'] != null &&
                          widget.quiz['key'].toString().isNotEmpty) {
                        if (widget.quiz['key'].toString() == key.toString()) {
                          facultyId =
                              value['createdBy']?.toString() ?? facultyId;
                          facultyName =
                              value['createdByName']?.toString() ?? facultyName;
                          found = true;
                        }
                      } else if (matchesQuiz(value)) {
                        facultyId = value['createdBy']?.toString() ?? facultyId;
                        facultyName =
                            value['createdByName']?.toString() ?? facultyName;
                        found = true;
                      }
                    }
                  }
                }
                if (found) break;
              }
              print(
                  'Debug: RTDB lookup finished, found=$found facultyId="$facultyId" facultyName="$facultyName"');
            }
          }
        } catch (e) {
          print('Error resolving quiz creator from Realtime DB: $e');
        }
      }

      final codingAnswersList =
          List.generate(questions.length, (i) => codingAnswers[i] ?? '');
      final codingLanguagesList = List.generate(
        questions.length,
        (i) => (codingLanguages[i] ?? ProgrammingLanguage.python).name,
      );
      final subjectiveAnswersList =
          List.generate(questions.length, (i) => subjectiveAnswers[i] ?? '');
      final subjectiveMatchedKeywordsMap = <String, List<String>>{};
      for (int i = 0; i < subjectiveMatchedKeywordsByQuestion.length; i++) {
        subjectiveMatchedKeywordsMap[i.toString()] =
            List<String>.from(subjectiveMatchedKeywordsByQuestion[i]);
      }

      final submission = {
        'quizId': widget.quiz['id'] ?? widget.quiz['key'] ?? '',
        'quizTitle': widget.quiz['title'] ?? '',
        'subjectLabel':
            (widget.subject['label'] ?? widget.subject['id'] ?? '').toString(),
        'subjectKey': subjectKey,
        'subjectId': rawSubjectId,
        'unit': widget.quiz['unit'] ?? '',
        'facultyId': facultyId,
        'facultyName': facultyName,
        'studentId': studentId,
        'studentName': studentName,
        'enrollmentNumber': studentEnrollment,
        'enrollmentNo': studentEnrollment,
        'answers': userAnswers,
        'codingAnswers': codingAnswersList,
        'codingLanguages': codingLanguagesList,
        'subjectiveAnswers': subjectiveAnswersList,
        'correctAnswers': score,
        'percentage': percentage,
        'totalMarks': totalMarks,
        'marksFromCorrect': marksFromCorrect,
        'marksFromPartial': marksFromPartial,
        'codingTestCasesPassed': codingTestCasesPassed,
        'codingTestCasesTotal': codingTestCasesTotal,
        'codingTestCasesPassedByQuestion': codingTestCasesPassedByQuestion,
        'codingTestCasesTotalByQuestion': codingTestCasesTotalByQuestion,
        'subjectiveKeywordScoreByQuestion': subjectiveKeywordScoreByQuestion,
        'subjectiveMatchedKeywordsByQuestion': subjectiveMatchedKeywordsMap,
        'subjectiveTotalKeywordsByQuestion': subjectiveTotalKeywordsByQuestion,
        'earnedMarksByQuestion': earnedMarksByQuestion,
        'possibleMarksByQuestion': possibleMarksByQuestion,
        'questionIdentityByQuestion': questions.asMap().entries.map((entry) {
          final question = entry.value;
          final tag = AssessmentTaggingService.extractTag(question);
          return {
            'stableQuestionId': tag?['stableQuestionId'] ??
                question['stableQuestionId'] ??
                question['id'] ??
                question['questionId'],
            'sourceFingerprint': tag?['sourceFingerprint'] ??
                question['assessmentTagSourceFingerprint'] ??
                AssessmentTaggingService.buildQuestionFingerprint(question),
          };
        }).toList(),
        'timeTakenSeconds': timeTaken.inSeconds,
        'completionReason': completionReason,
        'autoTerminated': autoTerminated,
        'status': autoTerminated ? 'terminated_focus_loss' : 'submitted',
        'timestamp': FieldValue.serverTimestamp(),
        // mark as sent to faculty immediately when student submits
        'sentToFaculty': FieldValue.serverTimestamp(),
        // store the quiz data so faculty can review questions with answers
        'quizData': widget.quiz,
        // store the exact question/option order used for this attempt
        'attemptQuestions': List.from(
            questions.map((q) => Map<String, dynamic>.from(q)).toList()),
      };

      final docRef = await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .add(submission);
      submissionDocId = docRef.id;
      print(
          'Submission saved with id: ${docRef.id} and facultyId: ${submission['facultyId']} subjectLabel: ${submission['subjectLabel']}');
      // Read back the saved document to confirm what was written
      try {
        final saved = await docRef.get();
        if (saved.exists) {
          final savedData = saved.data();
          print('Saved doc data: $savedData');
        } else {
          print('Saved doc not found after write (unexpected)');
        }
      } catch (e) {
        print('Error reading back saved submission: $e');
      }
      // Show brief confirmation to student (non-blocking)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              autoTerminated
                  ? 'Quiz auto-ended due to screen/tab change. Results sent to faculty.'
                  : 'Quiz submitted successfully. Results sent to faculty.',
            ),
          ),
        );
      }
    } catch (e) {
      print('Error saving quiz submission: $e');
    }

    // Navigate to detailed results screen, pass submission doc id so results can be sent/updated
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => QuizResultsScreen(
          quiz: widget.quiz,
          subject: widget.subject,
          questions: questions,
          userAnswers: userAnswers,
          correctAnswers: score,
          percentage: percentage,
          timeTaken: timeTaken,
          submissionDocId: submissionDocId,
          codingAnswers: codingAnswers,
          codingLanguages: codingLanguages,
          subjectiveAnswers: subjectiveAnswers,
          totalMarks: totalMarks,
          earnedMarksByQuestion: earnedMarksByQuestion,
          possibleMarksByQuestion: possibleMarksByQuestion,
          taxonomyNodes: taxonomyNodes,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  ProgrammingLanguage _getProgrammingLanguage(String? langStr) {
    if (langStr == null) return ProgrammingLanguage.python;
    try {
      return ProgrammingLanguage.values.firstWhere(
        (e) => e.name == langStr,
        orElse: () => ProgrammingLanguage.python,
      );
    } catch (e) {
      return ProgrammingLanguage.python;
    }
  }

  String _languageLabel(ProgrammingLanguage lang) {
    switch (lang) {
      case ProgrammingLanguage.python:
        return 'Python';
      case ProgrammingLanguage.java:
        return 'Java';
      case ProgrammingLanguage.cpp:
        return 'C++';
      case ProgrammingLanguage.javascript:
        return 'JavaScript';
      case ProgrammingLanguage.dart:
        return 'Dart';
    }
  }

  double _questionMaxMarks(Map<String, dynamic> question) {
    final type = (question['type'] ?? '').toString();
    if (type == 'coding' ||
        type == 'subjective' ||
        type == 'image' ||
        type == 'mcq' ||
        type.isEmpty) {
      final v = question['marks'];
      if (v is int) return v.toDouble();
      if (v is double) return v;
      if (v is String) return double.tryParse(v) ?? 1.0;
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadySubmitted) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.quiz['title'] ?? 'Quiz'),
          backgroundColor: widget.subject['color'],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'You have already attempted this quiz. Multiple attempts are not allowed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16)),
                SizedBox(height: 12),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Back')),
              ],
            ),
          ),
        ),
      );
    }

    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Quiz'),
          backgroundColor: widget.subject['color'],
        ),
        body: Center(
          child: Text('No questions available for this quiz.'),
        ),
      );
    }

    Map<String, dynamic> currentQuestion = questions[currentQuestionIndex];
    String questionType = (currentQuestion['type'] ?? 'mcq').toString();
    List<String> options = List<String>.from(currentQuestion['options'] ?? []);

    if (questionType == 'subjective') {
      _syncSubjectiveControllerIfNeeded();
    }

    return WillPopScope(
      onWillPop: () async {
        if (quizCompleted || _isSubmitting || _alreadySubmitted) return true;
        _completeQuiz(
          reason: 'left_quiz_screen',
          autoTerminated: true,
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: primaryWhite,
        appBar: AppBar(
          title: Text(widget.quiz['title']),
          backgroundColor: widget.subject['color'],
          foregroundColor: Colors.white,
          actions: [
            Container(
              margin: EdgeInsets.all(8),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer, size: 16),
                  SizedBox(width: 4),
                  Text(
                    _formatTime(timeRemaining),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Progress indicator
            Container(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Question ${currentQuestionIndex + 1} of ${questions.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: primaryBar,
                        ),
                      ),
                      Text(
                        '${((currentQuestionIndex + 1) / questions.length * 100).toStringAsFixed(0)}% Complete',
                        style: TextStyle(
                          color: primaryBar.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (currentQuestionIndex + 1) / questions.length,
                    backgroundColor: Colors.grey[300],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(widget.subject['color']),
                  ),
                ],
              ),
            ),

            // Question content
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question type badge
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: questionType == 'coding'
                                  ? Colors.purple.shade100
                                  : questionType == 'subjective'
                                      ? Colors.teal.shade100
                                      : questionType == 'image'
                                          ? Colors.teal.shade100
                                          : Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  questionType == 'coding'
                                      ? Icons.code
                                      : questionType == 'subjective'
                                          ? Icons.edit_note
                                          : questionType == 'image'
                                              ? Icons.image
                                              : Icons.quiz,
                                  size: 16,
                                  color: questionType == 'coding'
                                      ? Colors.purple.shade700
                                      : questionType == 'subjective'
                                          ? Colors.teal.shade700
                                          : questionType == 'image'
                                              ? Colors.teal.shade700
                                              : Colors.blue.shade700,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  questionType == 'coding'
                                      ? 'Coding Question'
                                      : questionType == 'subjective'
                                          ? 'Subjective'
                                          : questionType == 'image'
                                              ? 'Image Question'
                                              : 'Multiple Choice',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: questionType == 'coding'
                                        ? Colors.purple.shade700
                                        : questionType == 'subjective'
                                            ? Colors.teal.shade700
                                            : questionType == 'image'
                                                ? Colors.teal.shade700
                                                : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 16),

                          // Question
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              currentQuestion['question'] ?? '',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: primaryBar,
                                height: 1.4,
                              ),
                            ),
                          ),

                          if ((currentQuestion['imageUrl'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.white,
                                child: Image.network(
                                  (currentQuestion['imageUrl'] ?? '')
                                      .toString(),
                                  height: 220,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 80,
                                      alignment: Alignment.center,
                                      color: Colors.grey[200],
                                      child: Text('Failed to load image'),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],

                          SizedBox(height: 20),

                          // Render based on question type
                          if (questionType == 'coding') ...[
                            // Coding question UI
                            // Show test cases if available
                            if (currentQuestion['testCases'] != null &&
                                (currentQuestion['testCases'] as List)
                                    .isNotEmpty)
                              TestCasesDisplay(
                                testCases:
                                    (currentQuestion['testCases'] as List)
                                        .map((tc) => TestCase.fromMap(
                                            tc as Map<String, dynamic>))
                                        .toList(),
                              ),

                            SizedBox(height: 16),

                            Row(
                              children: [
                                Text(
                                  'Language:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                SizedBox(width: 12),
                                DropdownButton<ProgrammingLanguage>(
                                  value:
                                      codingLanguages[currentQuestionIndex] ??
                                          _getProgrammingLanguage(
                                              currentQuestion['language']
                                                  ?.toString()),
                                  items: ProgrammingLanguage.values
                                      .map(
                                        (lang) => DropdownMenuItem<
                                            ProgrammingLanguage>(
                                          value: lang,
                                          child: Text(_languageLabel(lang)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (newLang) {
                                    if (newLang == null) return;
                                    setState(() {
                                      codingLanguages[currentQuestionIndex] =
                                          newLang;
                                    });
                                  },
                                ),
                              ],
                            ),
                            SizedBox(height: 12),

                            // Code editor
                            Container(
                              height: 400,
                              color: Colors.black,
                              child: CodeEditorWidget(
                                language:
                                    codingLanguages[currentQuestionIndex] ??
                                        _getProgrammingLanguage(
                                            currentQuestion['language']
                                                ?.toString()),
                                initialCode:
                                    codingAnswers[currentQuestionIndex] ?? '',
                                onCodeChanged: (code) {
                                  if (codingAnswers[currentQuestionIndex] !=
                                      code) {
                                    codingAnswers[currentQuestionIndex] = code;
                                    // Safely triggers setState even if the framework is currently building
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) setState(() {});
                                    });
                                  }
                                },
                              ),
                            ),
                          ] else if (questionType == 'subjective') ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: TextField(
                                controller: _subjectiveController,
                                maxLines: 6,
                                decoration: InputDecoration(
                                  hintText: 'Type your answer here',
                                  border: InputBorder.none,
                                ),
                                onChanged: (value) {
                                  subjectiveAnswers[currentQuestionIndex] =
                                      value;
                                },
                              ),
                            ),
                          ] else if (questionType == 'image') ...[
                            // Image Question rendering
                            if ((currentQuestion['imageQuestionContent'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.white,
                                  child: Image.network(
                                    (currentQuestion['imageQuestionContent'] ??
                                            '')
                                        .toString(),
                                    height: 300,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 150,
                                        alignment: Alignment.center,
                                        color: Colors.grey[200],
                                        child: Text('Failed to load image'),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(height: 20),
                            ],

                            // Check if it's MCQ or subjective answer type
                            if ((currentQuestion['imageAnswerType'] ??
                                        'subjective')
                                    .toString() ==
                                'mcq') ...[
                              // MCQ style answers for image question
                              ...options.asMap().entries.map((entry) {
                                int index = entry.key;
                                String option = entry.value;
                                bool isSelected =
                                    selectedAnswers[currentQuestionIndex] ==
                                        index;

                                return Container(
                                  margin: EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    onTap: () => _selectAnswer(index),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? widget.subject['color']
                                                .withOpacity(0.1)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? widget.subject['color']
                                              : Colors.grey[300]!,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isSelected
                                                    ? widget.subject['color']
                                                    : Colors.grey[400]!,
                                                width: 2,
                                              ),
                                            ),
                                            child: isSelected
                                                ? Center(
                                                    child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: widget
                                                            .subject['color'],
                                                      ),
                                                    ),
                                                  )
                                                : SizedBox(),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: primaryBar,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ] else ...[
                              // Text answer for image question
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: TextField(
                                  controller: _subjectiveController,
                                  maxLines: 6,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Type your answer based on the image',
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (value) {
                                    subjectiveAnswers[currentQuestionIndex] =
                                        value;
                                  },
                                ),
                              ),
                            ],
                          ] else ...[
                            // MCQ Options
                            ...options.asMap().entries.map((entry) {
                              int index = entry.key;
                              String option = entry.value;
                              bool isSelected =
                                  selectedAnswers[currentQuestionIndex] ==
                                      index;

                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () => _selectAnswer(index),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? widget.subject['color']
                                              .withOpacity(0.1)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? widget.subject['color']
                                            : Colors.grey[300]!,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? widget.subject['color']
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: isSelected
                                                  ? widget.subject['color']
                                                  : Colors.grey[400]!,
                                            ),
                                          ),
                                          child: isSelected
                                              ? Icon(Icons.check,
                                                  color: Colors.white, size: 16)
                                              : null,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            option,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: primaryBar,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (questionType == 'coding') ...[
                    SizedBox(height: 10),
                    // ACTION BUTTONS: Skip, Run Tests, Submit
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 16),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: _showTestResults,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text('Run Tests',
                                style: TextStyle(color: Colors.white)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              // Mark as answered for tracking (empty is allowed and scores 0).
                              selectedAnswers[currentQuestionIndex] = 1;
                              _nextQuestion();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text('Submit Answer',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Navigation buttons
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  if (currentQuestionIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousQuestion,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: widget.subject['color']),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Previous',
                          style: TextStyle(color: widget.subject['color']),
                        ),
                      ),
                    ),
                  if (currentQuestionIndex > 0) SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (currentQuestion['type'] == 'coding' ||
                              currentQuestion['type'] == 'subjective' ||
                              selectedAnswers[currentQuestionIndex] != null)
                          ? (currentQuestionIndex == questions.length - 1
                              ? _completeQuiz
                              : _nextQuestion)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.subject['color'],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        currentQuestionIndex == questions.length - 1
                            ? 'Complete Quiz'
                            : (currentQuestion['type'] == 'coding'
                                ? 'Skip & Next'
                                : 'Next Question'),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
