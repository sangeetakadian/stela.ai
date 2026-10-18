import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:pdf_text/pdf_text.dart'; // Removed: not available
// For docx parsing, you may use: import 'package:docx_parse/docx_parse.dart'; (add to pubspec if needed)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../firebase_options.dart';
import '../models/quiz_model.dart';
import '../widgets/coding_question_form.dart';
import '../widgets/assessment_tag_editor.dart';
import '../services/assessment_tagging_service.dart';
import '../services/quiz_service.dart';
import '../services/taxonomy_service.dart';
import '../widgets/taxonomy_management_dialog.dart';

class FacultyQuizManage extends StatefulWidget {
  final dynamic subject;
  const FacultyQuizManage({required this.subject});

  @override
  State<FacultyQuizManage> createState() => _FacultyQuizManageState();
}

class _FacultyQuizManageState extends State<FacultyQuizManage> {
  // Safe accessor for subject as Map<String, dynamic>
  Map<String, dynamic> get subject =>
      Map<String, dynamic>.from(widget.subject as Map);

  late DatabaseReference _quizRef;
  List<Map<String, dynamic>> previousQuizzes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initFirebaseAndLoad();
  }

  Future<void> _deleteQuiz(String key, String? unitName) async {
    try {
      bool deleted = false;

      if (unitName != null) {
        // Try to delete from specific unit first (new structure)
        final unitRef = _quizRef.child(unitName.replaceAll(' ', '_'));
        final unitSnapshot = await unitRef.child(key).get();
        if (unitSnapshot.exists) {
          await unitRef.child(key).remove();
          deleted = true;
        }
      }

      if (!deleted) {
        // Fallback: search through all possible locations
        final snapshot = await _quizRef.get();
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;

          // First, try to find in unit-based structure
          for (var unitKey in data.keys) {
            if (data[unitKey] is Map) {
              final unitData = data[unitKey] as Map<dynamic, dynamic>;
              if (unitData.containsKey(key)) {
                await _quizRef.child(unitKey).child(key).remove();
                deleted = true;
                break;
              }
            }
          }

          // If still not found, try direct quiz structure (old format)
          if (!deleted && data.containsKey(key)) {
            await _quizRef.child(key).remove();
            deleted = true;
          }
        }
      }

      if (deleted) {
        await _loadQuizzes();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quiz deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quiz not found or already deleted.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error deleting quiz: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting quiz: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _initFirebaseAndLoad() async {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);

      // Get a safe ID from the subject Map (could be id, value or label)
      final dynamic subjectObj = widget.subject;
      String rawId = 'general';
      if (subjectObj is Map) {
        rawId = (subjectObj['id'] ??
                subjectObj['value'] ??
                subjectObj['label'] ??
                'general')
            .toString();
      } else if (subjectObj != null) {
        rawId = subjectObj.toString();
      }

      final String subjectId = rawId.toLowerCase();
      final String subjectKey = QuizService.mapSubjectIdToFacultyKey(subjectId);

      print(
          'FacultyQuizManage: Initializing for subject raw ID "$subjectId" with key "$subjectKey"');
      _quizRef =
          FirebaseDatabase.instance.ref().child('quizzes').child(subjectKey);
      await _migrateOldQuizzes(); // Migrate old quizzes to new structure
      await _loadQuizzes();
    } catch (e) {
      print('Firebase Init Error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _migrateOldQuizzes() async {
    try {
      final snapshot = await _quizRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        bool migrationNeeded = false;
        Map<String, dynamic> quizzesToMigrate = {};

        // Find old-style direct quizzes that need migration
        data.forEach((key, value) {
          if (value is Map &&
              value.containsKey('title') &&
              value.containsKey('questions')) {
            // This is a direct quiz (old format)
            String unitName = value['unit']?.toString() ?? 'Unit 1';
            quizzesToMigrate[key.toString()] = {
              'quiz': value,
              'unit': unitName,
            };
            migrationNeeded = true;
            print('Found old quiz to migrate: ${value['title']} -> $unitName');
          }
        });

        if (migrationNeeded) {
          print(
              'Migrating ${quizzesToMigrate.length} old quizzes to new unit structure...');

          // Migrate each quiz to the proper unit structure
          for (var entry in quizzesToMigrate.entries) {
            String oldKey = entry.key;
            Map<dynamic, dynamic> quizData = entry.value['quiz'];
            String unitName = entry.value['unit'];

            // Create new quiz in unit structure
            final unitRef = _quizRef.child(unitName.replaceAll(' ', '_'));
            final newRef = unitRef.push();
            await newRef.set(quizData);

            // Remove old direct quiz
            await _quizRef.child(oldKey).remove();

            print('Migrated quiz "${quizData['title']}" to unit "$unitName"');
          }

          print('Migration completed successfully!');
        }
      }
    } catch (e) {
      print('Error during quiz migration: $e');
    }
  }

  Future<void> _loadQuizzes() async {
    try {
      final snapshot = await _quizRef.get();
      List<Map<String, dynamic>> loaded = [];
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        // Handle both old structure (direct quizzes) and new structure (unit-based)
        data.forEach((key, value) {
          if (value is Map) {
            // Check if this is a unit (contains nested quizzes) or a direct quiz
            bool isUnit = false;
            value.forEach((subKey, subValue) {
              if (subValue is Map &&
                  subValue.containsKey('title') &&
                  subValue.containsKey('questions')) {
                isUnit = true;
                loaded.add({
                  'key': subKey,
                  'title': subValue['title']?.toString() ?? '',
                  'date': subValue['date']?.toString() ?? '',
                  'unit': subValue['unit']?.toString() ??
                      key.toString().replaceAll('_', ' '),
                  'originalUnit': key
                      .toString()
                      .replaceAll('_', ' '), // Track original unit for editing
                  'questions': subValue['questions'] ?? [],
                  'duration': subValue['duration']?.toString() ?? '30 min',
                  'pin': subValue['pin']?.toString() ?? '',
                });
              }
            });

            // If not a unit, treat as direct quiz (backward compatibility)
            if (!isUnit && value.containsKey('title')) {
              loaded.add({
                'key': key,
                'title': value['title']?.toString() ?? '',
                'date': value['date']?.toString() ?? '',
                'unit': value['unit']?.toString() ?? 'Unit 1',
                'questions': value['questions'] ?? [],
                'duration': value['duration']?.toString() ?? '30 min',
                'pin': value['pin']?.toString() ?? '',
              });
            }
          }
        });
      }
      setState(() {
        previousQuizzes = loaded;
      });
    } catch (e) {
      print('Error loading quizzes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addQuiz(dynamic quizData) async {
    final date = DateTime.now().toString().substring(0, 10);
    final unitName = quizData is Map && quizData['unit'] != null
        ? quizData['unit']
        : 'Unit 1';
    final duration = quizData is Map && quizData['duration'] != null
        ? '${quizData['duration']} min'
        : '30 min';
    final pin =
        quizData is Map && quizData['pin'] != null ? quizData['pin'] : '';

    final rawQuestions = quizData is Map && quizData['questions'] != null
        ? List<Map<String, dynamic>>.from((quizData['questions'] as List)
            .map((q) => Map<String, dynamic>.from(q as Map)))
        : <Map<String, dynamic>>[];
    final persistableQuestions =
        AssessmentTaggingService.stripTagFields(rawQuestions);

    double computeTotalMarks(List questions) {
      double sum = 0;
      for (final q in questions) {
        if (q is Map) {
          final type = (q['type'] ?? '').toString();
          if (type == 'coding' || type == 'subjective') {
            final v = q['marks'];
            if (v is int) {
              sum += v.toDouble();
            } else if (v is double) {
              sum += v;
            } else if (v is String) {
              sum += double.tryParse(v) ?? 1.0;
            } else {
              sum += 1.0;
            }
          } else {
            sum += 1.0;
          }
        } else {
          sum += 1.0;
        }
      }
      return sum;
    }

    final questionsList = quizData is Map && quizData['questions'] != null
        ? (quizData['questions'] as List)
        : <dynamic>[];
    final newQuiz = {
      'title': quizData is String ? quizData : quizData['title'],
      'date': date,
      'unit': unitName,
      'questions': persistableQuestions,
      'facultyQuestions': persistableQuestions,
      'duration': duration,
      'pin': pin,
      'instructions': quizData is Map && quizData['instructions'] != null
          ? quizData['instructions']
          : '',
      'totalMarks': persistableQuestions.isNotEmpty
          ? computeTotalMarks(persistableQuestions)
          : 0,
      // Track which faculty created this quiz
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdByName': FirebaseAuth.instance.currentUser?.displayName ?? '',
    };

    // Store quiz under the specific unit
    final unitRef = _quizRef.child(unitName.replaceAll(' ', '_'));
    final newRef = unitRef.push();
    await newRef.set(newQuiz);
    final subjectKey = QuizService.mapSubjectIdToFacultyKey(
      (widget.subject is Map
              ? widget.subject['id'] ??
                  widget.subject['value'] ??
                  widget.subject['label'] ??
                  'general'
              : widget.subject.toString())
          .toString(),
    );
    await AssessmentTaggingService.persistQuizQuestionTags(
      subjectKey: subjectKey,
      quizId: newRef.key ?? DateTime.now().millisecondsSinceEpoch.toString(),
      questions: rawQuestions,
    );
    setState(() {
      previousQuizzes.add({
        'key': newRef.key,
        'title': newQuiz['title'],
        'date': date,
        'unit': unitName,
        'questions': newQuiz['questions'],
        'pin': pin
      });
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Quiz added to $unitName!')));
  }

  Future<void> _editQuiz(
      String key, String originalUnit, dynamic quizData) async {
    final newUnitName = quizData['unit'] ?? 'Unit 1';
    final originalUnitName = originalUnit;
    final duration =
        quizData['duration'] != null ? '${quizData['duration']} min' : '30 min';
    final pin = quizData['pin'] ?? '';
    final rawQuestions = (quizData['questions'] ?? []) is List
        ? List<Map<String, dynamic>>.from((quizData['questions'] as List)
            .map((q) => Map<String, dynamic>.from(q as Map)))
        : <Map<String, dynamic>>[];
    final persistableQuestions =
        AssessmentTaggingService.stripTagFields(rawQuestions);

    double computeTotalMarks(List questions) {
      double sum = 0;
      for (final q in questions) {
        if (q is Map) {
          final type = (q['type'] ?? '').toString();
          if (type == 'coding' || type == 'subjective') {
            final v = q['marks'];
            if (v is int) {
              sum += v.toDouble();
            } else if (v is double) {
              sum += v;
            } else if (v is String) {
              sum += double.tryParse(v) ?? 1.0;
            } else {
              sum += 1.0;
            }
          } else {
            sum += 1.0;
          }
        } else {
          sum += 1.0;
        }
      }
      return sum;
    }

    final questionsList = rawQuestions;

    final updatedQuiz = {
      'title': quizData['title'],
      'date': quizData['date'] ?? DateTime.now().toString().substring(0, 10),
      'unit': newUnitName,
      'questions': persistableQuestions,
      'facultyQuestions': persistableQuestions,
      'duration': duration,
      'pin': pin,
      'instructions': quizData['instructions'] ?? '',
      'totalMarks':
          (questionsList is List) ? computeTotalMarks(persistableQuestions) : 0,
      // Preserve or set the creator
      'createdBy':
          quizData['createdBy'] ?? FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdByName': quizData['createdByName'] ??
          FirebaseAuth.instance.currentUser?.displayName ??
          '',
    };

    final subjectKey = QuizService.mapSubjectIdToFacultyKey(
      (widget.subject is Map
              ? widget.subject['id'] ??
                  widget.subject['value'] ??
                  widget.subject['label'] ??
                  'general'
              : widget.subject.toString())
          .toString(),
    );

    // If unit has changed, we need to move the quiz
    if (originalUnitName != newUnitName) {
      // Delete from original unit
      final originalUnitRef =
          _quizRef.child(originalUnitName.replaceAll(' ', '_'));
      await originalUnitRef.child(key).remove();

      // Add to new unit with new key
      final newUnitRef = _quizRef.child(newUnitName.replaceAll(' ', '_'));
      final newRef = newUnitRef.push();
      await newRef.set(updatedQuiz);
      await AssessmentTaggingService.persistQuizQuestionTags(
        subjectKey: subjectKey,
        quizId: newRef.key ?? key,
        questions: rawQuestions,
      );

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Quiz moved from $originalUnitName to $newUnitName!')));
    } else {
      // Update in the same unit
      final unitRef = _quizRef.child(newUnitName.replaceAll(' ', '_'));
      await unitRef.child(key).set(updatedQuiz);
      await AssessmentTaggingService.persistQuizQuestionTags(
        subjectKey: subjectKey,
        quizId: key,
        questions: rawQuestions,
      );

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quiz updated in $newUnitName!')));
    }

    await _loadQuizzes();
  }

  Future<void> _processExcelFile(FilePickerResult result,
      {String? unitName}) async {
    try {
      print('Starting Excel file processing...');

      // Step 1: Read file bytes
      Uint8List bytes;
      final picked = result.files.single;
      if (picked.bytes == null) {
        throw Exception('Could not read the selected file. Please try again.');
      }
      bytes = picked.bytes!;
      print(
          '${kIsWeb ? 'Web' : 'Device'}: File read successfully, bytes: ${bytes.length}');

      // Step 2: Parse Excel - try the original approach for all platforms
      List<Map<String, dynamic>> questions = [];
      try {
        print('Attempting to decode Excel file...');
        final excel = xl.Excel.decodeBytes(bytes);
        print(
            'Excel decoded successfully, tables: ${excel.tables.keys.length}');

        bool parseBool(dynamic v) {
          if (v == null) return false;
          final s = v.toString().trim().toLowerCase();
          return s == 'true' || s == '1' || s == 'yes' || s == 'y';
        }

        int parseCorrectIndex(String answerValue) {
          final v = answerValue.trim().toUpperCase();
          if (v == 'A' || v == '1') return 0;
          if (v == 'B' || v == '2') return 1;
          if (v == 'C' || v == '3') return 2;
          if (v == 'D' || v == '4') return 3;
          final numAnswer = int.tryParse(v);
          if (numAnswer != null && numAnswer >= 1 && numAnswer <= 4)
            return numAnswer - 1;
          return 0;
        }

        String? cellString(
            List<xl.Data?> row, Map<String, int> headers, List<String> names) {
          String? cellValueToString(dynamic v) {
            if (v == null) return null;
            try {
              final inner = (v as dynamic).value;
              if (inner != null) return inner.toString();
            } catch (_) {}
            return v.toString();
          }

          for (final name in names) {
            final idx = headers[name];
            if (idx != null && idx >= 0 && idx < row.length) {
              final v = row[idx]?.value;
              if (v != null) {
                final s = cellValueToString(v) ?? '';
                if (s.trim().isNotEmpty) return s;
              }
            }
          }
          return null;
        }

        String unescapeCodeText(String s) {
          // Allows paste-safe Excel content like "\\n" to become real newlines in the app editor.
          // Do NOT apply this to JSON cells like testCases.
          return s
              .replaceAll('\\r\\n', '\n')
              .replaceAll('\\n', '\n')
              .replaceAll('\\t', '\t');
        }

        int? cellInt(
            List<xl.Data?> row, Map<String, int> headers, List<String> names) {
          final s = cellString(row, headers, names);
          if (s == null) return null;
          return int.tryParse(s.trim());
        }

        Map<String, int> buildHeaders(List<xl.Data?> headerRow) {
          final headers = <String, int>{};
          for (int i = 0; i < headerRow.length; i++) {
            final v = headerRow[i]?.value;
            if (v == null) continue;
            final key = v.toString().trim().toLowerCase();
            if (key.isEmpty) continue;
            headers[key] = i;
          }
          return headers;
        }

        ProgrammingLanguage parseLanguage(String? raw) {
          final s = (raw ?? '').trim().toLowerCase();
          switch (s) {
            case 'java':
              return ProgrammingLanguage.java;
            case 'cpp':
            case 'c++':
              return ProgrammingLanguage.cpp;
            case 'javascript':
            case 'js':
              return ProgrammingLanguage.javascript;
            case 'dart':
              return ProgrammingLanguage.dart;
            case 'python':
            default:
              return ProgrammingLanguage.python;
          }
        }

        List<String> parseKeywords(String? raw) {
          if (raw == null || raw.trim().isEmpty) return <String>[];
          return raw
              .split(RegExp(r'[,;\n]+'))
              .map((k) => k.trim().toLowerCase())
              .where((k) => k.isNotEmpty)
              .toSet()
              .toList();
        }

        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table]!;
          bool isHeaderRow = true;
          print('Processing sheet: $table with ${sheet.rows.length} rows');

          Map<String, int> headers = {};
          bool useHeaderFormat = false;

          for (int r = 0; r < sheet.rows.length; r++) {
            final row = sheet.rows[r];
            if (isHeaderRow) {
              headers = buildHeaders(row);
              useHeaderFormat = headers.containsKey('type') ||
                  headers.containsKey('question_type') ||
                  headers.containsKey('questiontype');
              isHeaderRow = false;
              continue;
            }

            if (useHeaderFormat) {
              final typeRaw = cellString(row, headers,
                      ['type', 'question_type', 'questiontype']) ??
                  '';
              final type = typeRaw.trim().toLowerCase();
              final questionText =
                  cellString(row, headers, ['question', 'q']) ?? '';

              if (questionText.trim().isEmpty) continue;

              if (type == 'coding') {
                final lang = parseLanguage(
                    cellString(row, headers, ['language', 'lang']));
                final marks = cellInt(row, headers, ['marks']) ?? 1;
                final solutionCodeRaw = cellString(
                        row, headers, ['solutioncode', 'solution_code']) ??
                    '';
                final solutionCode = unescapeCodeText(solutionCodeRaw);

                List<Map<String, dynamic>> testCases = [];
                final testCasesJson =
                    cellString(row, headers, ['testcases', 'test_cases']);
                if (testCasesJson != null && testCasesJson.trim().isNotEmpty) {
                  try {
                    final decoded = jsonDecode(testCasesJson);
                    if (decoded is List) {
                      testCases = decoded
                          .whereType<Map>()
                          .map((m) => {
                                'input': (m['input'] ?? '').toString(),
                                'expectedOutput':
                                    (m['expectedOutput'] ?? m['output'] ?? '')
                                        .toString(),
                                'isHidden': m['isHidden'] == true,
                                'description':
                                    (m['description'] ?? '').toString(),
                              })
                          .toList();
                    }
                  } catch (_) {
                    // Ignore malformed JSON and fall back to column-based parsing.
                  }
                }

                if (testCases.isEmpty) {
                  // Try single test case columns
                  final singleInput = cellString(row, headers, ['input']);
                  final singleOut = cellString(row, headers,
                      ['expectedoutput', 'output', 'expected_output']);
                  if ((singleInput ?? '').trim().isNotEmpty ||
                      (singleOut ?? '').trim().isNotEmpty) {
                    testCases.add({
                      'input': (singleInput ?? '').toString(),
                      'expectedOutput': (singleOut ?? '').toString(),
                      'isHidden': false,
                      'description': '',
                    });
                  }
                }

                if (testCases.isEmpty) {
                  // Try numbered test case columns: input1/expectedOutput1[/description1/hidden1]
                  for (int i = 1; i <= 20; i++) {
                    final inKey = 'input$i';
                    final outKey = 'expectedoutput$i';
                    final outAltKey = 'output$i';
                    final descKey = 'description$i';
                    final hiddenKey = 'hidden$i';

                    final input = cellString(row, headers, [inKey]);
                    final out = cellString(row, headers, [outKey, outAltKey]);
                    final desc = cellString(row, headers, [descKey]) ?? '';
                    final hiddenRaw = cellString(row, headers, [hiddenKey]);

                    if ((input ?? '').trim().isEmpty &&
                        (out ?? '').trim().isEmpty &&
                        desc.trim().isEmpty &&
                        (hiddenRaw ?? '').trim().isEmpty) {
                      // stop when a whole slot is empty
                      continue;
                    }

                    if ((input ?? '').trim().isEmpty &&
                        (out ?? '').trim().isEmpty) continue;

                    testCases.add({
                      'input': (input ?? '').toString(),
                      'expectedOutput': (out ?? '').toString(),
                      'isHidden': parseBool(hiddenRaw),
                      'description': desc,
                    });
                  }
                }

                if (testCases.isEmpty) {
                  print(
                      'Skipping coding question with no test cases: $questionText');
                  continue;
                }

                final q = <String, dynamic>{
                  'type': 'coding',
                  'question': questionText,
                  'language': lang.name,
                  'marks': marks,
                  'solutionCode': solutionCode,
                  'testCases': testCases,
                };
                questions.add(q);
              } else if (type == 'subjective') {
                final marks = cellInt(row, headers, ['marks']) ?? 1;
                final expectedAnswer = cellString(
                        row, headers, ['expectedanswer', 'expected_answer']) ??
                    '';
                final keywordsRaw = cellString(row, headers,
                    ['keywords', 'keyword', 'key_terms', 'keyterms']);
                final keywords = parseKeywords(keywordsRaw);
                questions.add({
                  'type': 'subjective',
                  'question': questionText,
                  'marks': marks,
                  'expectedAnswer': expectedAnswer,
                  'keywords': keywords,
                });
              } else {
                // Default to MCQ
                final options = <String>[
                  cellString(
                          row, headers, ['optiona', 'a', 'opt1', 'option1']) ??
                      '',
                  cellString(
                          row, headers, ['optionb', 'b', 'opt2', 'option2']) ??
                      '',
                  cellString(
                          row, headers, ['optionc', 'c', 'opt3', 'option3']) ??
                      '',
                  cellString(
                          row, headers, ['optiond', 'd', 'opt4', 'option4']) ??
                      '',
                ];
                final answerValue =
                    cellString(row, headers, ['correct', 'answer', 'ans']) ??
                        'A';
                final correct = parseCorrectIndex(answerValue);

                if (options.any((opt) => opt.trim().isNotEmpty)) {
                  questions.add({
                    'type': 'mcq',
                    'question': questionText,
                    'options': options,
                    'correct': correct,
                  });
                }
              }
            } else {
              // Legacy MCQ-only: columns [question, A, B, C, D, correct]
              if (row.length >= 6 && row[0]?.value != null) {
                String question = row[0]?.value?.toString() ?? '';
                List<String> options = [
                  row[1]?.value?.toString() ?? '',
                  row[2]?.value?.toString() ?? '',
                  row[3]?.value?.toString() ?? '',
                  row[4]?.value?.toString() ?? '',
                ];

                String answerValue = row[5]?.value?.toString() ?? '';
                int correct = parseCorrectIndex(answerValue);

                if (question.isNotEmpty &&
                    options.any((opt) => opt.isNotEmpty)) {
                  questions.add({
                    'type': 'mcq',
                    'question': question,
                    'options': options,
                    'correct': correct,
                  });
                }
              }
            }
          }
        }
      } catch (e) {
        print('Excel parsing error: $e');
        print('Error type: ${e.runtimeType}');

        // If it's the namespace error, provide a more specific message
        if (e.toString().contains('_Namespace') ||
            e.toString().contains('Unsupported operation')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Excel processing failed on web. Please try using the mobile app or create quiz manually.'),
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        } else {
          throw Exception('Failed to parse Excel file: $e');
        }
      }

      print('Parsed ${questions.length} questions from Excel');

      // Step 3: Process results
      if (questions.isNotEmpty) {
        // Use file name (without extension) as quiz title
        String quizTitle = result.files.single.name;
        if (quizTitle.contains('.')) {
          quizTitle = quizTitle.substring(0, quizTitle.lastIndexOf('.'));
        }

        print('Attempting to add quiz: $quizTitle');

        // Step 4: Save to Firebase
        try {
          // Pass unitName through so uploaded quiz is stored under selected unit
          await _addQuiz(
              {'title': quizTitle, 'questions': questions, 'unit': unitName});
          print('Quiz added successfully to Firebase');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Quiz uploaded successfully with ${questions.length} questions!')),
            );
          }
        } catch (e) {
          print('Firebase save error: $e');
          throw Exception('Failed to save quiz to database: $e');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('No valid questions found in the uploaded file.')),
          );
        }
      }
    } catch (e) {
      print('Overall processing error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing file: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return Scaffold(
      appBar: AppBar(
        title: Text("Quizzes - ${subject['label']}"),
        backgroundColor: subject['color'],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Replace top-level buttons with a 4-unit panel below
                      // (UI now shows units with create/upload inside each)
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    "Units",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  SizedBox(height: 12),
                  // Determine units (ensure 4 units)
                  Builder(builder: (ctx) {
                    List<String> units;
                    if (widget.subject['units'] != null) {
                      units = (widget.subject['units'] as List<dynamic>)
                          .map((u) => u['name'].toString())
                          .toList();
                    } else {
                      units = ['Unit 1', 'Unit 2', 'Unit 3', 'Unit 4'];
                    }
                    // Ensure exactly 4 units
                    while (units.length < 4)
                      units.add('Unit ${units.length + 1}');
                    if (units.length > 4) units = units.sublist(0, 4);

                    // Group existing quizzes by unit
                    Map<String, List<Map<String, dynamic>>> quizzesByUnit = {};
                    for (var q in previousQuizzes) {
                      final unitName = (q['unit'] ?? 'Unit 1').toString();
                      quizzesByUnit.putIfAbsent(unitName, () => []).add(q);
                    }

                    return Expanded(
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 900 ? 2 : 1,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 3.2,
                        ),
                        itemCount: units.length,
                        itemBuilder: (context, idx) {
                          final unit = units[idx];
                          final unitQuizzes = quizzesByUnit[unit] ?? [];
                          return Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                          child: Text(unit,
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.add),
                                        label: Text('Create Quiz'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: subject['color']),
                                        onPressed: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    QuizCreationForm(
                                                        subject: subject,
                                                        initialUnit: unit)),
                                          );
                                          if (result != null &&
                                              result is Map &&
                                              result['title'] != null &&
                                              result['title']
                                                  .toString()
                                                  .isNotEmpty) {
                                            await _addQuiz(result);
                                          }
                                        },
                                      ),
                                      SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.upload_file),
                                        label: Text('Upload'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue),
                                        onPressed: () async {
                                          try {
                                            FilePickerResult? result =
                                                await FilePicker.platform
                                                    .pickFiles(
                                              type: FileType.custom,
                                              allowedExtensions: [
                                                'xlsx',
                                                'xls'
                                              ],
                                              withData: true,
                                            );
                                            if (result != null) {
                                              await _processExcelFile(result,
                                                  unitName: unit);
                                            }
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        'Error selecting file: ${e.toString()}')));
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Expanded(
                                    child: unitQuizzes.isEmpty
                                        ? Center(
                                            child: Text(
                                                'No quizzes in this unit',
                                                style: TextStyle(
                                                    color: Colors.grey)))
                                        : ListView.builder(
                                            itemCount: unitQuizzes.length,
                                            itemBuilder: (c, i) {
                                              final quiz = unitQuizzes[i];
                                              return ListTile(
                                                leading: Icon(Icons.quiz,
                                                    color: subject['color']),
                                                title:
                                                    Text(quiz['title'] ?? ''),
                                                subtitle: Text(
                                                    'Date: ${quiz['date'] ?? ''} | Duration: ${quiz['duration'] ?? ''}'),
                                                trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                          icon: Icon(Icons.edit,
                                                              color:
                                                                  Colors.blue),
                                                          onPressed: () async {
                                                            // Prepare questions list
                                                            List<
                                                                    Map<String,
                                                                        dynamic>>
                                                                questionsList =
                                                                [];
                                                            if (quiz[
                                                                    'questions'] !=
                                                                null) {
                                                              if (quiz[
                                                                      'questions']
                                                                  is List) {
                                                                questionsList = (quiz[
                                                                            'questions']
                                                                        as List)
                                                                    .map((q) => Map<
                                                                            String,
                                                                            dynamic>.from(
                                                                        q as Map))
                                                                    .toList();
                                                              } else if (quiz[
                                                                      'questions']
                                                                  is Map) {
                                                                final map =
                                                                    (quiz['questions']
                                                                        as Map);
                                                                final sortedKeys = map
                                                                    .keys
                                                                    .toList()
                                                                  ..sort((a, b) => a
                                                                      .toString()
                                                                      .compareTo(
                                                                          b.toString()));
                                                                questionsList = sortedKeys
                                                                    .map((k) => Map<
                                                                            String,
                                                                            dynamic>.from(
                                                                        map[k]))
                                                                    .toList();
                                                              }
                                                            }
                                                            try {
                                                              final subjectKey =
                                                                  QuizService
                                                                      .mapSubjectIdToFacultyKey(
                                                                (widget.subject
                                                                            is Map
                                                                        ? widget.subject['id'] ??
                                                                            widget.subject[
                                                                                'value'] ??
                                                                            widget.subject[
                                                                                'label'] ??
                                                                            'general'
                                                                        : widget
                                                                            .subject
                                                                            .toString())
                                                                    .toString(),
                                                              );
                                                              questionsList =
                                                                  await AssessmentTaggingService
                                                                      .loadQuizQuestionTags(
                                                                subjectKey:
                                                                    subjectKey,
                                                                quizId: quiz[
                                                                        'key']
                                                                    .toString(),
                                                                questions:
                                                                    questionsList,
                                                              );
                                                            } catch (error) {
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  SnackBar(
                                                                    content:
                                                                        Text(
                                                                      'Existing tags could not be loaded; tag metadata will not be modified: $error',
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                            final result =
                                                                await Navigator
                                                                    .push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder: (_) =>
                                                                    QuizCreationForm(
                                                                  subject:
                                                                      subject,
                                                                  initialTitle:
                                                                      quiz[
                                                                          'title'],
                                                                  initialQuestions:
                                                                      questionsList,
                                                                  initialDuration: quiz[
                                                                              'duration']
                                                                          is int
                                                                      ? quiz[
                                                                          'duration']
                                                                      : (quiz['duration']
                                                                              is String
                                                                          ? int.tryParse(
                                                                              quiz['duration'])
                                                                          : null),
                                                                  initialPin:
                                                                      quiz['pin']
                                                                              ?.toString() ??
                                                                          '',
                                                                  initialUnit:
                                                                      quiz[
                                                                          'unit'],
                                                                  initialInstructions:
                                                                      quiz['instructions']
                                                                              ?.toString() ??
                                                                          '',
                                                                ),
                                                              ),
                                                            );
                                                            if (result !=
                                                                null) {
                                                              await _editQuiz(
                                                                  quiz['key'],
                                                                  quiz['originalUnit'] ??
                                                                      quiz[
                                                                          'unit'],
                                                                  result);
                                                            }
                                                          }),
                                                      IconButton(
                                                          icon: Icon(
                                                              Icons.delete,
                                                              color: Colors
                                                                  .redAccent),
                                                          onPressed: () async {
                                                            final confirm = await showDialog<
                                                                    bool>(
                                                                context:
                                                                    context,
                                                                builder: (ctx) =>
                                                                    AlertDialog(
                                                                        title: Text(
                                                                            'Delete Quiz'),
                                                                        content:
                                                                            Text('Are you sure you want to delete "${quiz['title']}"?'),
                                                                        actions: [
                                                                          TextButton(
                                                                              onPressed: () => Navigator.pop(ctx, false),
                                                                              child: Text('Cancel')),
                                                                          TextButton(
                                                                              onPressed: () => Navigator.pop(ctx, true),
                                                                              child: Text('Delete'))
                                                                        ]));
                                                            if (confirm ==
                                                                true) {
                                                              await _deleteQuiz(
                                                                  quiz['key'],
                                                                  quiz['unit']);
                                                            }
                                                          })
                                                    ]),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class QuizCreationForm extends StatefulWidget {
  final dynamic subject;
  final String? initialTitle;
  final List<Map<String, dynamic>>? initialQuestions;
  final int? initialDuration;
  final String? initialPin;
  final String? initialUnit;
  final String? initialInstructions;
  const QuizCreationForm(
      {required this.subject,
      this.initialTitle,
      this.initialQuestions,
      this.initialDuration,
      this.initialPin,
      this.initialUnit,
      this.initialInstructions});

  @override
  _QuizCreationFormState createState() => _QuizCreationFormState();
}

class _QuizCreationFormState extends State<QuizCreationForm> {
  // Safe accessor for subject as Map<String, dynamic>
  Map<String, dynamic> get subject =>
      Map<String, dynamic>.from(widget.subject as Map);

  final _formKey = GlobalKey<FormState>();
  String quizTitle = "";
  String? selectedUnit;
  int duration = 30; // Default 30 minutes
  String pin = ""; // 6-digit PIN
  String instructions = "";
  List<String> availableUnits = [];
  List<Map<String, dynamic>> questions = [];

  Future<void> _pickAndUploadQuestionImage(int qIndex) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please sign in to upload an image.')),
        );
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (result == null) return;

      final picked = result.files.single;
      if (picked.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Could not read the selected image. Please try again.')),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: CircularProgressIndicator()),
      );

      final subjectLabel = (subject['label'] ?? 'subject').toString();
      final safeSubject =
          subjectLabel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = (picked.name.isNotEmpty ? picked.name : 'image_$ts')
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final storagePath =
          'quiz_question_images/${user.uid}/$safeSubject/q${qIndex + 1}_${ts}_$safeName';

      final ext = (picked.extension ?? '').toLowerCase();
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(
        picked.bytes!,
        SettableMetadata(contentType: contentType),
      );
      final url = await ref.getDownloadURL();

      print('Image uploaded successfully: $url');

      if (mounted) Navigator.pop(context); // close loader
      setState(() {
        questions[qIndex]['imageUrl'] = url;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Image upload error: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadImageQuestionContent(int qIndex) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please sign in to upload an image.')),
        );
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (result == null) return;

      final picked = result.files.single;
      if (picked.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Could not read the selected image. Please try again.')),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: CircularProgressIndicator()),
      );

      final subjectLabel = (subject['label'] ?? 'subject').toString();
      final safeSubject =
          subjectLabel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = (picked.name.isNotEmpty ? picked.name : 'image_$ts')
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final storagePath =
          'quiz_question_images/${user.uid}/$safeSubject/img_q${qIndex + 1}_${ts}_$safeName';

      final ext = (picked.extension ?? '').toLowerCase();
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(
        picked.bytes!,
        SettableMetadata(contentType: contentType),
      );
      final url = await ref.getDownloadURL();

      print('Image question content uploaded: $url');
      if (mounted) Navigator.pop(context); // close loader
      setState(() {
        questions[qIndex]['imageQuestionContent'] = url;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question image uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Image question content upload error: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    quizTitle = widget.initialTitle ?? "";
    duration = widget.initialDuration ?? 30;
    pin = widget.initialPin ?? "";
    instructions = widget.initialInstructions ?? "";

    // Initialize available units from subject data
    if (subject['units'] != null) {
      final unitsData = subject['units'];
      if (unitsData is List) {
        availableUnits = unitsData
            .map((unit) =>
                (unit is Map ? unit['name']?.toString() : unit?.toString()) ??
                '')
            .where((name) => name.isNotEmpty)
            .toList();
      }
    }

    if (availableUnits.isEmpty) {
      availableUnits = ['Unit 1', 'Unit 2', 'Unit 3', 'Unit 4'];
    }

    if (widget.initialQuestions != null) {
      questions = widget.initialQuestions!.map((dynamic q) {
        final Map<String, dynamic> questionMap =
            Map<String, dynamic>.from(q as Map);
        final type = (questionMap['type'] ?? '').toString();

        // Preserve coding and subjective as-is (they already store richer fields).
        if (type == 'coding' || type == 'subjective') {
          if (type == 'subjective') {
            final rawKeywords = questionMap['keywords'];
            if (rawKeywords is List) {
              questionMap['keywords'] = rawKeywords
                  .map((k) => k.toString().trim().toLowerCase())
                  .where((k) => k.isNotEmpty)
                  .toSet()
                  .toList();
            } else {
              questionMap['keywords'] = <String>[];
            }
          }
          return questionMap;
        } else {
          return {
            'type': 'mcq',
            'question': questionMap['question']?.toString() ?? '',
            'imageUrl': questionMap['imageUrl']?.toString(),
            'options': questionMap['options'] is List
                ? List<String>.from((questionMap['options'] as List)
                    .map((e) => e?.toString() ?? ''))
                : List<String>.filled(4, ''),
            'correct': _toInt(questionMap['correct']),
          };
        }
      }).toList();
    } else {
      questions = [];
    }

    // Preselect unit if provided
    selectedUnit = widget.initialUnit ?? selectedUnit;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<String> _parseKeywordInput(String raw) {
    if (raw.trim().isEmpty) return <String>[];
    return raw
        .split(RegExp(r'[,;\n]+'))
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList();
  }

  void _addMCQQuestion() {
    setState(() {
      questions.add({
        'type': 'mcq',
        'question': '',
        'imageUrl': null,
        'options': List<String>.filled(4, ''),
        'correct': null, // No option pre-selected
      });
    });
  }

  void _addSubjectiveQuestion() {
    setState(() {
      questions.add({
        'type': 'subjective',
        'question': '',
        'imageUrl': null,
        'marks': 1,
        'expectedAnswer': '',
        'keywords': <String>[],
      });
    });
  }

  void _addCodingQuestion() {
    showDialog(
      context: context,
      builder: (context) => CodingQuestionForm(
        onSave: (questionData) {
          setState(() {
            questions.add(questionData);
          });
          Navigator.pop(context);
        },
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  void _addImageQuestion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Image Question'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select answer type for image question:'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    questions.add({
                      'type': 'image',
                      'question': '',
                      'imageQuestionContent': null,
                      'imageAnswerType': 'mcq',
                      'options': List<String>.filled(4, ''),
                      'correct': null,
                    });
                  });
                },
                child: Text('Image with MCQ Options'),
              ),
              SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    questions.add({
                      'type': 'image',
                      'question': '',
                      'imageQuestionContent': null,
                      'imageAnswerType': 'subjective',
                      'marks': 1,
                      'expectedAnswer': '',
                      'keywords': <String>[],
                    });
                  });
                },
                child: Text('Image with Text Answer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editCodingQuestion(int index, Map<String, dynamic> question) {
    showDialog(
      context: context,
      builder: (context) => CodingQuestionForm(
        initialQuestion: question,
        onSave: (questionData) {
          setState(() {
            questions[index] = questionData;
          });
          Navigator.pop(context);
        },
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  String _generateRandomPin() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return (random % 900000 + 100000).toString(); // Ensures 6 digits
  }

  bool _validateCorrectAnswers() {
    for (var q in questions) {
      // MCQ questions need a correct answer selected
      if (q['type'] == 'mcq' && q['correct'] == null) return false;
      // Image MCQ questions need a correct answer selected
      if (q['type'] == 'image' &&
          (q['imageAnswerType'] ?? 'subjective').toString() == 'mcq' &&
          q['correct'] == null) return false;
      // Coding questions need at least one test case
      if (q['type'] == 'coding' &&
          (q['testCases'] == null || q['testCases'].isEmpty)) return false;
    }
    return true;
  }

  String _assessmentTagSummary(Map<String, dynamic> question) {
    final tag = question['assessmentTag'];
    if (tag is! Map || tag.isEmpty) {
      return 'Topics & Skills';
    }
    final conceptIds =
        tag['conceptIds'] is List ? (tag['conceptIds'] as List).length : 0;
    final skillIds = tag['assessedSkillIds'] is List
        ? (tag['assessedSkillIds'] as List).length
        : 0;
    if (conceptIds == 0 && skillIds == 0) {
      return 'Topics & Skills';
    }
    return '$conceptIds concept(s) • $skillIds skill(s)';
  }

  Future<void> _openAssessmentTagEditor(int questionIndex) async {
    final subjectKey = QuizService.mapSubjectIdToFacultyKey(
      (widget.subject is Map
              ? widget.subject['id'] ??
                  widget.subject['value'] ??
                  widget.subject['label'] ??
                  'general'
              : widget.subject.toString())
          .toString(),
    );

    try {
      final registry =
          await TaxonomyRegistry.loadFromFirebase(subjectKey: subjectKey);
      if (!mounted || questionIndex >= questions.length) {
        return;
      }

      final currentQuestion = questions[questionIndex];
      final dialogResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AssessmentTagEditorDialog(
          initialTag: currentQuestion['assessmentTag'] is Map
              ? Map<String, dynamic>.from(currentQuestion['assessmentTag'])
              : null,
          taxonomyRegistry: registry,
          sourceIsStale: currentQuestion['assessmentTagStale'] == true,
        ),
      );

      if (dialogResult != null && mounted && questionIndex < questions.length) {
        setState(() {
          questions[questionIndex]['assessmentTag'] = dialogResult;
          questions[questionIndex]['assessmentTagStale'] = false;
          questions[questionIndex]['assessmentTagSourceFingerprint'] =
              AssessmentTaggingService.buildQuestionFingerprint(
            questions[questionIndex],
          );
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load taxonomy: $error')),
        );
      }
    }
  }

  Future<void> _openTaxonomyManager() async {
    final subjectKey = QuizService.mapSubjectIdToFacultyKey(
      (widget.subject is Map
              ? widget.subject['id'] ??
                  widget.subject['value'] ??
                  widget.subject['label'] ??
                  'general'
              : widget.subject.toString())
          .toString(),
    );

    try {
      final initialRegistry =
          await TaxonomyRegistry.loadFromFirebase(subjectKey: subjectKey);

      if (!mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => TaxonomyManagementDialog(
          subjectKey: subjectKey,
          initialRegistry: initialRegistry,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load taxonomy: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return Scaffold(
      appBar: AppBar(
        title: Text("Create Quiz - ${subject['label']}"),
        backgroundColor: subject['color'],
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Manage taxonomy',
            onPressed: _openTaxonomyManager,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Quiz Title",
                    border: OutlineInputBorder(),
                  ),
                  initialValue: quizTitle,
                  validator: (value) => value == null || value.isEmpty
                      ? "Enter quiz title"
                      : null,
                  onSaved: (value) => quizTitle = value ?? "",
                  onChanged: (value) => quizTitle = value,
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Select Unit",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  value: selectedUnit,
                  items: availableUnits.map((String unit) {
                    return DropdownMenuItem<String>(
                      value: unit,
                      child: Text(unit),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedUnit = newValue;
                    });
                  },
                  validator: (value) =>
                      value == null ? "Please select a unit" : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Quiz Duration (minutes)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                    suffixText: "min",
                  ),
                  initialValue: duration.toString(),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Enter quiz duration";
                    }
                    final minutes = int.tryParse(value);
                    if (minutes == null || minutes <= 0) {
                      return "Enter a valid duration in minutes";
                    }
                    if (minutes > 300) {
                      return "Duration cannot exceed 300 minutes";
                    }
                    return null;
                  },
                  onSaved: (value) =>
                      duration = int.tryParse(value ?? "30") ?? 30,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      duration = parsed;
                    }
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Quiz Access PIN (6 digits, optional)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.refresh),
                      tooltip: "Generate Random PIN",
                      onPressed: () {
                        setState(() {
                          pin = _generateRandomPin();
                        });
                      },
                    ),
                    helperText:
                        "Optional: Students need this PIN to start the quiz (leave empty for no PIN)",
                  ),
                  initialValue: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (value.length != 6) {
                        return "PIN must be exactly 6 digits";
                      }
                      if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                        return "PIN must contain only numbers";
                      }
                    }
                    return null;
                  },
                  onSaved: (value) => pin = value ?? "",
                  onChanged: (value) => pin = value,
                ),
                SizedBox(height: 24),
                Text(
                  "Questions:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 12),
                // Instructions field
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Instructions (shown to students)",
                    hintText:
                        "Enter any instructions or guidelines for this quiz",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.info_outline),
                  ),
                  initialValue: instructions,
                  maxLines: 3,
                  onChanged: (v) => instructions = v,
                ),
                SizedBox(height: 12),
                ...questions.asMap().entries.map((entry) {
                  int qIndex = entry.key;
                  final q = Map<String, dynamic>.from(entry.value as Map);
                  final String questionType = q['type']?.toString() ?? 'mcq';

                  Color _badgeBg() {
                    if (questionType == 'coding') return Colors.purple.shade100;
                    if (questionType == 'subjective')
                      return Colors.orange.shade100;
                    if (questionType == 'image') return Colors.teal.shade100;
                    return Colors.blue.shade100;
                  }

                  Color _badgeFg() {
                    if (questionType == 'coding') return Colors.purple.shade700;
                    if (questionType == 'subjective')
                      return Colors.orange.shade700;
                    if (questionType == 'image') return Colors.teal.shade700;
                    return Colors.blue.shade700;
                  }

                  IconData _badgeIcon() {
                    if (questionType == 'coding') return Icons.code;
                    if (questionType == 'subjective') return Icons.subject;
                    if (questionType == 'image') return Icons.image;
                    return Icons.quiz;
                  }

                  String _badgeText() {
                    if (questionType == 'coding') return 'Coding Question';
                    if (questionType == 'subjective') return 'Subjective';
                    if (questionType == 'image') return 'Image Question';
                    return 'MCQ';
                  }

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question type badge
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _badgeBg(),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _badgeIcon(),
                                      size: 14,
                                      color: _badgeFg(),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      _badgeText(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _badgeFg(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Spacer(),
                              Text(
                                "Question ${qIndex + 1}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _openAssessmentTagEditor(qIndex),
                              icon: Icon(Icons.psychology_alt_outlined),
                              label: Text(_assessmentTagSummary(q)),
                            ),
                          ),
                          SizedBox(height: 12),

                          // Render based on question type
                          if (questionType == 'mcq') ...[
                            // MCQ Question rendering
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: "Question",
                                border: OutlineInputBorder(),
                              ),
                              initialValue: q['question'],
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? "Enter question"
                                      : null,
                              onChanged: (value) =>
                                  questions[qIndex]['question'] = value,
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(Icons.image),
                                  label: Text(
                                      ((questions[qIndex]['imageUrl'] ?? '')
                                              .toString()
                                              .isEmpty)
                                          ? 'Attach Image'
                                          : 'Change Image'),
                                  onPressed: () =>
                                      _pickAndUploadQuestionImage(qIndex),
                                ),
                                SizedBox(width: 12),
                                if ((questions[qIndex]['imageUrl'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        questions[qIndex]['imageUrl'] = null;
                                      });
                                    },
                                    child: Text('Remove'),
                                  ),
                              ],
                            ),
                            if ((questions[qIndex]['imageUrl'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  (questions[qIndex]['imageUrl'] ?? '')
                                      .toString(),
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      Container(
                                    height: 80,
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: Text('Failed to load image preview'),
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: 12),
                            ...List.generate(
                                4,
                                (optIdx) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: Row(
                                        children: [
                                          Radio<int>(
                                            value: optIdx,
                                            groupValue: q['correct'],
                                            onChanged: (val) {
                                              setState(() {
                                                questions[qIndex]['correct'] =
                                                    val;
                                              });
                                            },
                                          ),
                                          Expanded(
                                            child: TextFormField(
                                              decoration: InputDecoration(
                                                labelText:
                                                    "Option ${optIdx + 1}",
                                                border: OutlineInputBorder(),
                                              ),
                                              initialValue: q['options']
                                                  [optIdx],
                                              validator: (value) =>
                                                  value == null || value.isEmpty
                                                      ? "Enter option"
                                                      : null,
                                              onChanged: (value) =>
                                                  questions[qIndex]['options']
                                                      [optIdx] = value,
                                            ),
                                          ),
                                          if (q['correct'] == optIdx)
                                            Container(
                                              margin: EdgeInsets.only(left: 8),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text("Correct",
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                    )),
                            if (q['correct'] == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  "Please select the correct answer",
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12),
                                ),
                              ),
                          ] else if (questionType == 'subjective') ...[
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Question',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: (q['question'] ?? '').toString(),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter question'
                                      : null,
                              onChanged: (value) =>
                                  questions[qIndex]['question'] = value,
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(Icons.image),
                                  label: Text(
                                      ((questions[qIndex]['imageUrl'] ?? '')
                                              .toString()
                                              .isEmpty)
                                          ? 'Attach Image'
                                          : 'Change Image'),
                                  onPressed: () =>
                                      _pickAndUploadQuestionImage(qIndex),
                                ),
                                SizedBox(width: 12),
                                if ((questions[qIndex]['imageUrl'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        questions[qIndex]['imageUrl'] = null;
                                      });
                                    },
                                    child: Text('Remove'),
                                  ),
                              ],
                            ),
                            if ((questions[qIndex]['imageUrl'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  (questions[qIndex]['imageUrl'] ?? '')
                                      .toString(),
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      Container(
                                    height: 80,
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: Text('Failed to load image preview'),
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: 12),
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Marks',
                                hintText: 'e.g., 2, 5, 10',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              initialValue: (q['marks'] ?? 1).toString(),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty)
                                  return 'Required';
                                final parsed = int.tryParse(value.trim());
                                if (parsed == null) return 'Invalid number';
                                if (parsed <= 0) return 'Marks must be > 0';
                                return null;
                              },
                              onChanged: (value) => questions[qIndex]['marks'] =
                                  int.tryParse(value.trim()) ??
                                      (q['marks'] ?? 1),
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Expected Answer (optional)',
                                border: OutlineInputBorder(),
                              ),
                              initialValue:
                                  (q['expectedAnswer'] ?? '').toString(),
                              maxLines: 3,
                              onChanged: (value) =>
                                  questions[qIndex]['expectedAnswer'] = value,
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Keywords for auto-grading',
                                hintText:
                                    'e.g. tcp, three way handshake, sequence number',
                                border: OutlineInputBorder(),
                                helperText:
                                    'Comma, semicolon, or newline separated',
                              ),
                              initialValue: ((q['keywords'] as List?) ??
                                      const <dynamic>[])
                                  .map((k) => k.toString())
                                  .where((k) => k.trim().isNotEmpty)
                                  .join(', '),
                              maxLines: 3,
                              onChanged: (value) {
                                questions[qIndex]['keywords'] =
                                    _parseKeywordInput(value);
                              },
                            ),
                          ] else if (questionType == 'image') ...[
                            // Image Question rendering
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: "Question Text",
                                hintText:
                                    'Describe what to look for in the image',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: q['question'],
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? "Enter question"
                                      : null,
                              onChanged: (value) =>
                                  questions[qIndex]['question'] = value,
                            ),
                            SizedBox(height: 12),
                            // Image upload for main content
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(Icons.image),
                                  label: Text(((questions[qIndex]
                                                  ['imageQuestionContent'] ??
                                              '')
                                          .toString()
                                          .isEmpty)
                                      ? 'Upload Question Image'
                                      : 'Change Image'),
                                  onPressed: () =>
                                      _pickAndUploadImageQuestionContent(
                                          qIndex),
                                ),
                                SizedBox(width: 12),
                                if ((questions[qIndex]
                                            ['imageQuestionContent'] ??
                                        '')
                                    .toString()
                                    .isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        questions[qIndex]
                                            ['imageQuestionContent'] = null;
                                      });
                                    },
                                    child: Text('Remove'),
                                  ),
                              ],
                            ),
                            if ((questions[qIndex]['imageQuestionContent'] ??
                                    '')
                                .toString()
                                .isNotEmpty) ...[
                              SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  (questions[qIndex]['imageQuestionContent'] ??
                                          '')
                                      .toString(),
                                  height: 250,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      Container(
                                    height: 100,
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: Text('Failed to load image preview'),
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: 12),
                            Text(
                              'Answer Type: ${(q['imageAnswerType'] ?? 'subjective').toString().toUpperCase()}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 12),
                            if ((q['imageAnswerType'] ?? 'subjective')
                                    .toString() ==
                                'mcq') ...[
                              ...List.generate(
                                  4,
                                  (optIdx) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          children: [
                                            Radio<int>(
                                              value: optIdx,
                                              groupValue: q['correct'],
                                              onChanged: (val) {
                                                setState(() {
                                                  questions[qIndex]['correct'] =
                                                      val;
                                                });
                                              },
                                            ),
                                            Expanded(
                                              child: TextFormField(
                                                decoration: InputDecoration(
                                                  labelText:
                                                      "Option ${optIdx + 1}",
                                                  border: OutlineInputBorder(),
                                                ),
                                                initialValue: q['options']
                                                    [optIdx],
                                                validator: (value) =>
                                                    value == null ||
                                                            value.isEmpty
                                                        ? "Enter option"
                                                        : null,
                                                onChanged: (value) =>
                                                    questions[qIndex]['options']
                                                        [optIdx] = value,
                                              ),
                                            ),
                                            if (q['correct'] == optIdx)
                                              Container(
                                                margin:
                                                    EdgeInsets.only(left: 8),
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text("Correct",
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ),
                                          ],
                                        ),
                                      )),
                              if (q['correct'] == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    "Please select the correct answer",
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 12),
                                  ),
                                ),
                            ] else ...[
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Marks',
                                  hintText: 'e.g., 2, 5, 10',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                initialValue: (q['marks'] ?? 1).toString(),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty)
                                    return 'Required';
                                  final parsed = int.tryParse(value.trim());
                                  if (parsed == null) return 'Invalid number';
                                  if (parsed <= 0) return 'Marks must be > 0';
                                  return null;
                                },
                                onChanged: (value) => questions[qIndex]
                                        ['marks'] =
                                    int.tryParse(value.trim()) ??
                                        (q['marks'] ?? 1),
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Expected Answer (optional)',
                                  border: OutlineInputBorder(),
                                ),
                                initialValue:
                                    (q['expectedAnswer'] ?? '').toString(),
                                maxLines: 3,
                                onChanged: (value) =>
                                    questions[qIndex]['expectedAnswer'] = value,
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Keywords for auto-grading',
                                  hintText: 'e.g. mitochondria, nucleus, dna',
                                  border: OutlineInputBorder(),
                                  helperText:
                                      'Comma, semicolon, or newline separated',
                                ),
                                initialValue: ((q['keywords'] as List?) ??
                                        const <dynamic>[])
                                    .map((k) => k.toString())
                                    .where((k) => k.trim().isNotEmpty)
                                    .join(', '),
                                maxLines: 3,
                                onChanged: (value) {
                                  questions[qIndex]['keywords'] =
                                      _parseKeywordInput(value);
                                },
                              ),
                            ],
                          ] else ...[
                            // Coding Question rendering (summary view)
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    q['question'] ?? 'No question text',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.computer,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                      SizedBox(width: 4),
                                      Text(
                                        'Language: ${q['language'] ?? 'python'}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                      ),
                                      SizedBox(width: 16),
                                      Icon(Icons.emoji_events_outlined,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                      SizedBox(width: 4),
                                      Text(
                                        'Marks: ${q['marks'] ?? 1}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                      ),
                                      SizedBox(width: 16),
                                      Icon(Icons.check_circle_outline,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                      SizedBox(width: 4),
                                      Text(
                                        'Test Cases: ${q['testCases']?.length ?? 0}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    icon: Icon(Icons.edit, size: 16),
                                    label: Text('Edit Coding Question'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.purple.shade300,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        _editCodingQuestion(qIndex, q),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Delete button (common for all types)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    questions.removeAt(qIndex);
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.quiz),
                      label: Text("Add MCQ"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: subject['color'],
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addMCQQuestion,
                    ),
                    SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: Icon(Icons.code),
                      label: Text("Add Coding Question"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addCodingQuestion,
                    ),
                    SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: Icon(Icons.subject),
                      label: Text('Add Subjective'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addSubjectiveQuestion,
                    ),
                    SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: Icon(Icons.image),
                      label: Text('Add Image Question'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addImageQuestion,
                    ),
                  ],
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  child: Text("Save Quiz"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: subject['color'],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();
                      if (questions.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Add at least one question.')),
                        );
                        return;
                      }
                      if (!_validateCorrectAnswers()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Select the correct answer for every question.')),
                        );
                        return;
                      }
                      if (selectedUnit == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Please select a unit for this quiz.')),
                        );
                        return;
                      }
                      // Return a map with title, questions, unit, duration, pin, and instructions
                      Navigator.pop(context, {
                        'title': quizTitle,
                        'questions': questions,
                        'unit': selectedUnit,
                        'duration': duration,
                        'pin': pin,
                        'instructions': instructions,
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
