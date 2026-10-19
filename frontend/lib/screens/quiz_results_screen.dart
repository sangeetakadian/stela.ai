import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:stela_app/widgets/code_editor_widget.dart';
import 'package:stela_app/models/quiz_model.dart';
import '../models/assessment_tagging.dart';
import '../services/assessment_feedback_service.dart';
import '../services/assessment_tagging_service.dart';

class QuizResultsScreen extends StatefulWidget {
  final Map<String, dynamic> quiz;
  final Map<String, dynamic> subject;
  final List<Map<String, dynamic>> questions;
  final List<dynamic> userAnswers;
  final double correctAnswers;
  final double percentage;
  final double totalMarks;
  final Duration timeTaken;
  final String? submissionDocId;
  final Map<int, String> codingAnswers;
  final Map<int, ProgrammingLanguage> codingLanguages;
  final Map<int, String> subjectiveAnswers;
  final List<double> earnedMarksByQuestion;
  final List<double> possibleMarksByQuestion;
  final Map<String, TaxonomyNode> taxonomyNodes;
  final bool assessmentTagsLoadFailed;
  const QuizResultsScreen({
    Key? key,
    required this.quiz,
    required this.subject,
    required this.questions,
    required this.userAnswers,
    required this.correctAnswers,
    required this.percentage,
    required this.timeTaken,
    this.totalMarks = 0.0,
    this.submissionDocId,
    this.codingAnswers = const {},
    this.codingLanguages = const {},
    this.subjectiveAnswers = const {},
    this.earnedMarksByQuestion = const [],
    this.possibleMarksByQuestion = const [],
    this.taxonomyNodes = const {},
    this.assessmentTagsLoadFailed = false,
  }) : super(key: key);

  @override
  _QuizResultsScreenState createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends State<QuizResultsScreen> {
  final Map<int, double> _codingScores = <int, double>{};
  final Map<int, int> _codingPassed = <int, int>{};
  final Map<int, int> _codingTotal = <int, int>{};
  bool _codingEvaluated = false;

  double get _computedTotalMarks {
    if (widget.totalMarks > 0) return widget.totalMarks;
    double sum = 0;
    for (final q in widget.questions) {
      sum += _questionMaxMarks(q);
    }
    return sum;
  }

  double get _overallPercentage {
    final denom = _computedTotalMarks > 0 ? _computedTotalMarks : 1;
    return (widget.correctAnswers / denom) * 100.0;
  }

  List<AssessmentFeedbackItem> get _assessmentFeedback =>
      AssessmentFeedbackService.summarizeQuiz(
        questions: widget.questions,
        earnedMarksByQuestion: widget.earnedMarksByQuestion,
        possibleMarksByQuestion: widget.possibleMarksByQuestion,
        taxonomyNodes: widget.taxonomyNodes,
      );

  @override
  void initState() {
    super.initState();
    _evaluateCodingQuestions();
  }

  Future<void> _evaluateCodingQuestions() async {
    try {
      for (int i = 0; i < widget.questions.length; i++) {
        final q = widget.questions[i];
        final type = (q['type'] ?? '').toString();
        if (type != 'coding') continue;

        final code = widget.codingAnswers[i] ?? '';
        final testCases = (q['testCases'] ?? []) as List;
        final solutionCode = q['solutionCode']?.toString() ?? '';
        final studentLanguage = widget.codingLanguages[i] ??
            _getProgrammingLanguage(q['language']?.toString());
        final facultyLanguage =
            _getProgrammingLanguage(q['language']?.toString());

        if (code.trim().isEmpty) {
          _codingScores[i] = 0.0;
          _codingPassed[i] = 0;
          _codingTotal[i] = testCases.length;
          continue;
        }

        if (testCases.isNotEmpty) {
          final results = await SimulatedCodeRunner.runTests(
            code: code,
            testCasesData: testCases,
            language: studentLanguage,
            solutionLanguage: facultyLanguage,
            solutionCode: solutionCode,
            skipDelay: true,
          );
          final passed = results.where((r) => r.isPassed).length;
          _codingPassed[i] = passed;
          _codingTotal[i] = testCases.length;
          _codingScores[i] =
              testCases.isEmpty ? 0.0 : (passed / testCases.length);
        } else {
          // No test cases and no solution code: cannot grade reliably
          _codingPassed[i] = 0;
          _codingTotal[i] = 0;
          _codingScores[i] = 0.0;
        }
      }
    } catch (e) {
      // If anything goes wrong, don't crash results screen.
      debugPrint('Error evaluating coding questions for results screen: $e');
    }

    if (!mounted) return;
    setState(() {
      _codingEvaluated = true;
    });
  }

  ProgrammingLanguage _getProgrammingLanguage(String? langStr) {
    if (langStr == null) return ProgrammingLanguage.python;
    try {
      return ProgrammingLanguage.values.firstWhere(
        (e) => e.name == langStr,
        orElse: () => ProgrammingLanguage.python,
      );
    } catch (_) {
      return ProgrammingLanguage.python;
    }
  }

  String _fmtScore(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Quiz Results',
          style: TextStyle(
            fontFamily: 'PTSerif',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: widget.subject['color'],
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () {
            Navigator.pop(context); // Go back to subject detail
          },
        ),
      ),
      body: Column(
        children: [
          // Header with overall results
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: widget.subject['color'],
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  // Quiz title
                  Text(
                    widget.quiz['title'] ?? 'Quiz Results',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'PTSerif',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),

                  // Score circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 3,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_overallPercentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _overallPercentage >= 70
                                ? Colors.green
                                : Colors.orange,
                            fontFamily: 'PTSerif',
                          ),
                        ),
                        Text(
                          '${_fmtScore(widget.correctAnswers)}/${_fmtScore(_computedTotalMarks)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontFamily: 'PTSerif',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),

                  // Performance message
                  Text(
                    _getPerformanceMessage(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontFamily: 'PTSerif',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Statistics cards
          Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Score',
                    _fmtScore(widget.correctAnswers),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Max Score',
                    _fmtScore(_computedTotalMarks),
                    Colors.red,
                    Icons.flag,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Time Taken',
                    _formatDuration(widget.timeTaken),
                    Colors.blue,
                    Icons.timer,
                  ),
                ),
              ],
            ),
          ),

          _buildAssessmentFeedbackCard(),

          // Question-wise analysis header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.analytics, color: widget.subject['color']),
                SizedBox(width: 8),
                Text(
                  'Question Analysis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.subject['color'],
                    fontFamily: 'PTSerif',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),

          // Question-wise results
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.questions.length,
              itemBuilder: (context, index) {
                return _buildQuestionCard(index);
              },
            ),
          ),

          // Action buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Go back to subject detail
                        },
                        icon: Icon(Icons.home, size: 20),
                        label: Text(
                          'Back to Subject',
                          style: TextStyle(
                              fontFamily: 'PTSerif',
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.subject['color'],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      // Feedback button
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(
                              'https://docs.google.com/forms/d/e/1FAIpQLSe4S0tVb06rrhOYuMaBdAfJaH0UtUslYvfTQcWw67feXAOeLw/viewform?usp=dialog');
                          try {
                            if (!await launchUrl(uri,
                                mode: LaunchMode.externalApplication)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Could not open feedback form.')));
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error opening feedback form.')));
                          }
                        },
                        icon: Icon(Icons.feedback, size: 20),
                        label: Text(
                          'Give Feedback',
                          style: TextStyle(
                              fontFamily: 'PTSerif',
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: widget.subject['color'],
                          padding: EdgeInsets.symmetric(
                              vertical: 12, horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: widget.subject['color']),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'PTSerif',
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontFamily: 'PTSerif',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentFeedbackCard() {
    final feedback = _assessmentFeedback;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assessment evidence',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'A summary of reviewed tags for this quiz only; it is not a measure of overall ability.',
              ),
              const SizedBox(height: 8),
              if (feedback.isEmpty)
                Text(
                  widget.assessmentTagsLoadFailed
                      ? "Tag data could not be loaded. Check student read access to this quiz's assessment tags in Firebase."
                      : 'No reviewed concept or skill tags were found. Confirm the faculty saved the tagged quiz.',
                )
              else ...[
                if (!feedback.any(
                  (item) => item.kind == TaxonomyNodeKind.concept,
                ))
                  const Text('Concepts: Not assessed'),
                if (!feedback.any(
                  (item) => item.kind == TaxonomyNodeKind.skill,
                ))
                  const Text('Skills: Not assessed'),
                ...feedback.map((item) {
                  final canShowScore = item.possibleMarks > 0 &&
                      (item.kind == TaxonomyNodeKind.concept ||
                          item.status == 'Based on this quiz');
                  final scoreText = canShowScore
                      ? '${_fmtScore(item.earnedMarks)}/${_fmtScore(item.possibleMarks)} (${(item.ratio * 100).toStringAsFixed(0)}%)'
                      : item.status;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.kind == TaxonomyNodeKind.concept ? 'Concept' : 'Skill'}: ${item.label}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$scoreText • ${item.distinctQuestionCount} item(s)',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCompetencyEvidence(
    int index,
    Map<String, dynamic> question,
  ) {
    if (widget.assessmentTagsLoadFailed) {
      return const Text(
        'Question-level evidence: Tag data could not be loaded',
      );
    }
    final rawTag = question['assessmentTag'];
    if (rawTag is! Map) {
      return const Text('Question-level evidence: Not assessed');
    }

    final tag = Map<String, dynamic>.from(rawTag);
    final sourceFingerprint = tag['sourceFingerprint']?.toString();
    final currentFingerprint =
        question['assessmentTagSourceFingerprint']?.toString() ??
            AssessmentTaggingService.buildQuestionFingerprint(question);
    if (tag['reviewed'] != true ||
        question['assessmentTagStale'] == true ||
        sourceFingerprint == null ||
        sourceFingerprint.isEmpty ||
        sourceFingerprint != currentFingerprint) {
      return const Text('Question-level evidence: Mapping requires review');
    }

    List<String> labelsFor(String idKey, String labelKey) {
      final rawIds = tag[idKey];
      if (rawIds is! List) {
        return const [];
      }
      final rawLabels = tag[labelKey];
      final labels = rawLabels is Map
          ? Map<String, dynamic>.from(rawLabels)
          : const <String, dynamic>{};
      final resolvedLabels = <String>{};
      for (final value in rawIds) {
        final id = value.toString();
        final snapshot = labels[id]?.toString().trim();
        resolvedLabels.add(
          snapshot == null || snapshot.isEmpty
              ? widget.taxonomyNodes[id]?.name ?? id
              : snapshot,
        );
      }
      final sortedLabels = resolvedLabels.toList()..sort();
      return sortedLabels;
    }

    final concepts = labelsFor('conceptIds', 'conceptLabels');
    final skills = labelsFor('assessedSkillIds', 'skillLabels');
    if (concepts.isEmpty && skills.isEmpty) {
      return const Text(
          'Question-level evidence: No confirmed competency tags');
    }

    final hasValidScore = index < widget.earnedMarksByQuestion.length &&
        index < widget.possibleMarksByQuestion.length &&
        widget.earnedMarksByQuestion[index].isFinite &&
        widget.possibleMarksByQuestion[index].isFinite &&
        widget.possibleMarksByQuestion[index] > 0 &&
        widget.earnedMarksByQuestion[index] >= 0 &&
        widget.earnedMarksByQuestion[index] <=
            widget.possibleMarksByQuestion[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Question-level evidence',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (concepts.isNotEmpty) Text('Concepts: ${concepts.join(', ')}'),
        if (skills.isNotEmpty) Text('Skills: ${skills.join(', ')}'),
        Text(
          hasValidScore
              ? 'Score: ${_fmtScore(widget.earnedMarksByQuestion[index])}/${_fmtScore(widget.possibleMarksByQuestion[index])} marks'
              : 'Score unavailable',
        ),
      ],
    );
  }

  Widget _buildQuestionCard(int index) {
    final question = widget.questions[index];
    final userAnswer = widget.userAnswers[index];
    final type = (question['type'] ?? '').toString();
    final correctAnswer = question['correct'];

    final bool isCoding = type == 'coding';
    final bool isImageMcq = type == 'image' &&
        (question['imageAnswerType'] ?? 'subjective').toString() == 'mcq';
    final bool isSubjective = type == 'subjective' ||
        (type == 'image' &&
            (question['imageAnswerType'] ?? 'subjective').toString() ==
                'subjective');
    final double? codingScore = isCoding ? _codingScores[index] : null;
    final double maxMarks = _questionMaxMarks(question);
    final String subjectiveAnswer = isSubjective
        ? ((widget.subjectiveAnswers[index] ?? '').toString())
        : '';
    final List<String> subjectiveKeywords =
        isSubjective ? _extractQuestionKeywords(question) : const <String>[];
    final List<String> matchedKeywords = isSubjective
        ? _matchKeywordsInAnswer(subjectiveAnswer, subjectiveKeywords)
        : const <String>[];
    final double subjectiveScore =
        (isSubjective && subjectiveKeywords.isNotEmpty)
            ? (matchedKeywords.length / subjectiveKeywords.length) * maxMarks
            : 0.0;

    final bool isMcqCorrect = ((!isCoding && !isSubjective) || isImageMcq) &&
        userAnswer != null &&
        correctAnswer != null &&
        userAnswer == correctAnswer;
    final double earnedMarks = isCoding
        ? ((codingScore ?? 0.0) * maxMarks)
        : isSubjective
            ? subjectiveScore
            : (isMcqCorrect ? maxMarks : 0.0);

    final bool isFullCorrect = isCoding
        ? ((codingScore ?? 0.0) >= 0.999)
        : (isSubjective
            ? (subjectiveKeywords.isNotEmpty &&
                matchedKeywords.length == subjectiveKeywords.length)
            : isMcqCorrect);
    final bool isPartial = isCoding &&
        _codingEvaluated &&
        (codingScore ?? 0.0) > 0.0 &&
        (codingScore ?? 0.0) < 0.999;
    final bool isCorrect = isFullCorrect;

    final bool isSubjectiveUngraded =
        isSubjective && subjectiveKeywords.isEmpty;
    final bool isPartialSubjective = isSubjective &&
        subjectiveKeywords.isNotEmpty &&
        matchedKeywords.isNotEmpty &&
        matchedKeywords.length < subjectiveKeywords.length;
    final bool isUngraded = isSubjectiveUngraded;

    final Color borderColor = isUngraded
        ? Colors.blueGrey
        : ((isPartial || isPartialSubjective)
            ? Colors.orange
            : (isFullCorrect ? Colors.green : Colors.red));
    final IconData statusIcon = isUngraded
        ? Icons.pending_actions
        : ((isPartial || isPartialSubjective)
            ? Icons.change_circle
            : (isFullCorrect ? Icons.check_circle : Icons.cancel));
    final String statusText = isUngraded
        ? 'Ungraded'
        : ((isPartial || isPartialSubjective)
            ? 'Partial'
            : (isFullCorrect ? 'Correct' : 'Incorrect'));

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question header
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: borderColor,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PTSerif',
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        statusIcon,
                        color: borderColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: borderColor,
                          fontFamily: 'PTSerif',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Question text
            Text(
              question['question'] ?? '',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'PTSerif',
              ),
            ),
            SizedBox(height: 12),
            _buildQuestionCompetencyEvidence(index, question),
            SizedBox(height: 12),

            // Image for image questions
            if (type == 'image' &&
                (question['imageQuestionContent'] ?? '')
                    .toString()
                    .isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  (question['imageQuestionContent'] ?? '').toString(),
                  height: 250,
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
              SizedBox(height: 12),
            ],

            // Answer details
            if (isCoding) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.code, color: Colors.purple),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _codingEvaluated
                            ? 'Marks: ${_fmtScore(earnedMarks)}/${_fmtScore(maxMarks)}  (Passed: ${_codingPassed[index] ?? 0}/${_codingTotal[index] ?? 0})'
                            : 'Evaluating coding question...',
                        style: TextStyle(
                          fontFamily: 'PTSerif',
                          color: Colors.purple[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isSubjective) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSubjectiveUngraded
                          ? 'Marks: 0/${_fmtScore(maxMarks)} (pending review)'
                          : 'Marks: ${_fmtScore(earnedMarks)}/${_fmtScore(maxMarks)} (auto-graded)',
                      style: TextStyle(
                        fontFamily: 'PTSerif',
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your answer:',
                      style: TextStyle(
                          fontFamily: 'PTSerif', fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subjectiveAnswer.trim().isEmpty
                          ? '(No answer submitted)'
                          : subjectiveAnswer,
                      style: TextStyle(fontFamily: 'PTSerif'),
                    ),
                  ],
                ),
              ),
            ] else
              ...List.generate(question['options']?.length ?? 0, (optionIndex) {
                final option = question['options'][optionIndex];
                final isUserAnswer = userAnswer == optionIndex;
                final isCorrectAnswer = correctAnswer == optionIndex;

                Color optionColor = Colors.grey[200]!;
                Color textColor = Colors.black;
                IconData? optionIcon;

                if (isCorrectAnswer) {
                  optionColor = Colors.green.withOpacity(0.2);
                  textColor = Colors.green[800]!;
                  optionIcon = Icons.check_circle;
                } else if (isUserAnswer && !isCorrect) {
                  optionColor = Colors.red.withOpacity(0.2);
                  textColor = Colors.red[800]!;
                  optionIcon = Icons.cancel;
                }

                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: optionColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCorrectAnswer
                          ? Colors.green
                          : (isUserAnswer && !isCorrect)
                              ? Colors.red
                              : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${String.fromCharCode(65 + optionIndex)}. ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontFamily: 'PTSerif',
                        ),
                      ),
                      Expanded(
                        child: Text(
                          option ?? '',
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'PTSerif',
                          ),
                        ),
                      ),
                      if (optionIcon != null)
                        Icon(
                          optionIcon,
                          color: isCorrectAnswer ? Colors.green : Colors.red,
                          size: 20,
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _getPerformanceMessage() {
    final p = _overallPercentage;
    if (p >= 90) return '🎉 Excellent! Outstanding performance!';
    if (p >= 80) return '👏 Great job! You\'re doing very well!';
    if (p >= 70) return '👍 Good work! Keep it up!';
    if (p >= 60) return '📚 Not bad! A bit more practice will help!';
    return '💪 Keep practicing! You\'ll improve with time!';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
