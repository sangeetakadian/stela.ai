enum QuestionType {
  mcq,
  coding,
  subjective,
  image,
}

enum ProgrammingLanguage {
  python,
  java,
  cpp,
  javascript,
  dart,
}

class QuizQuestion {
  final String id;
  final QuestionType type;
  final String question;

  // Optional image for the question prompt (works for any type)
  final String? imageUrl;

  // MCQ specific fields
  final List<String>? options;
  final int? correctOptionIndex;

  // Coding specific fields
  final ProgrammingLanguage? language;
  final List<TestCase>? testCases;
  final String? expectedOutput;
  final String? solutionCode;

  // Subjective specific fields
  final String? expectedAnswer;
  final List<String>? keywords;

  // Image question specific fields
  final String? imageQuestionContent; // Image URL for image-based questions (primary content)
  final String? imageAnswerType; // "mcq" or "subjective" for image questions

  // Additional metadata that must survive round-trips even when the app does not
  // know the keys in advance. This preserves future/question-tagging fields without
  // rewriting the legacy serialised payload.
  final Map<String, dynamic> extraFields;

  QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.imageUrl,
    // MCQ fields
    this.options,
    this.correctOptionIndex,
    // Coding fields
    this.language,
    this.testCases,
    this.expectedOutput,
    this.solutionCode,
    // Subjective fields
    this.expectedAnswer,
    this.keywords,
    // Image question fields
    this.imageQuestionContent,
    this.imageAnswerType,
    this.extraFields = const {},
  });

  // Factory constructor for MCQ questions
  factory QuizQuestion.mcq({
    required String id,
    required String question,
    String? imageUrl,
    required List<String> options,
    required int correctOptionIndex,
  }) {
    return QuizQuestion(
      id: id,
      type: QuestionType.mcq,
      question: question,
      imageUrl: imageUrl,
      options: options,
      correctOptionIndex: correctOptionIndex,
    );
  }

  // Factory constructor for Coding questions
  factory QuizQuestion.coding({
    required String id,
    required String question,
    String? imageUrl,
    required ProgrammingLanguage language,
    List<TestCase>? testCases,
    String? expectedOutput,
    String? solutionCode,
  }) {
    return QuizQuestion(
      id: id,
      type: QuestionType.coding,
      question: question,
      imageUrl: imageUrl,
      language: language,
      testCases: testCases,
      expectedOutput: expectedOutput,
      solutionCode: solutionCode,
    );
  }

  factory QuizQuestion.subjective({
    required String id,
    required String question,
    String? imageUrl,
    String? expectedAnswer,
    List<String>? keywords,
  }) {
    return QuizQuestion(
      id: id,
      type: QuestionType.subjective,
      question: question,
      imageUrl: imageUrl,
      expectedAnswer: expectedAnswer,
      keywords: keywords,
    );
  }

  // Factory constructor for Image questions with MCQ answers
  factory QuizQuestion.imageMCQ({
    required String id,
    required String question,
    required String imageQuestionContent,
    required List<String> options,
    required int correctOptionIndex,
  }) {
    return QuizQuestion(
      id: id,
      type: QuestionType.image,
      question: question,
      imageQuestionContent: imageQuestionContent,
      imageAnswerType: 'mcq',
      options: options,
      correctOptionIndex: correctOptionIndex,
    );
  }

  // Factory constructor for Image questions with Subjective answers
  factory QuizQuestion.imageSubjective({
    required String id,
    required String question,
    required String imageQuestionContent,
    String? expectedAnswer,
    List<String>? keywords,
  }) {
    return QuizQuestion(
      id: id,
      type: QuestionType.image,
      question: question,
      imageQuestionContent: imageQuestionContent,
      imageAnswerType: 'subjective',
      expectedAnswer: expectedAnswer,
      keywords: keywords,
    );
  }

  // Convert to Map for Firebase storage
  QuizQuestion copyWith({
    String? id,
    QuestionType? type,
    String? question,
    String? imageUrl,
    List<String>? options,
    int? correctOptionIndex,
    ProgrammingLanguage? language,
    List<TestCase>? testCases,
    String? expectedOutput,
    String? solutionCode,
    String? expectedAnswer,
    List<String>? keywords,
    String? imageQuestionContent,
    String? imageAnswerType,
    Map<String, dynamic>? extraFields,
  }) {
    return QuizQuestion(
      id: id ?? this.id,
      type: type ?? this.type,
      question: question ?? this.question,
      imageUrl: imageUrl ?? this.imageUrl,
      options: options ?? this.options,
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
      language: language ?? this.language,
      testCases: testCases ?? this.testCases,
      expectedOutput: expectedOutput ?? this.expectedOutput,
      solutionCode: solutionCode ?? this.solutionCode,
      expectedAnswer: expectedAnswer ?? this.expectedAnswer,
      keywords: keywords ?? this.keywords,
      imageQuestionContent: imageQuestionContent ?? this.imageQuestionContent,
      imageAnswerType: imageAnswerType ?? this.imageAnswerType,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = {
      'id': id,
      'type': type.name,
      'question': question,
    };

    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      map['imageUrl'] = imageUrl;
    }

    if (type == QuestionType.mcq) {
      map['options'] = options ?? const [];
      map['correct'] = correctOptionIndex ?? 0;
    } else if (type == QuestionType.coding) {
      map['language'] = language?.name;
      map['testCases'] = testCases?.map((tc) => tc.toMap()).toList();
      map['expectedOutput'] = expectedOutput;
      map['solutionCode'] = solutionCode;
    } else if (type == QuestionType.subjective) {
      if (expectedAnswer != null && expectedAnswer!.trim().isNotEmpty) {
        map['expectedAnswer'] = expectedAnswer;
      }
      if (keywords != null && keywords!.isNotEmpty) {
        final normalized = keywords!
            .map((k) => k.trim())
            .where((k) => k.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) {
          map['keywords'] = normalized;
        }
      }
    } else if (type == QuestionType.image) {
      if (imageQuestionContent != null && imageQuestionContent!.trim().isNotEmpty) {
        map['imageQuestionContent'] = imageQuestionContent;
      }
      map['imageAnswerType'] = imageAnswerType ?? 'subjective';

      if (imageAnswerType == 'mcq') {
        map['options'] = options ?? const [];
        map['correct'] = correctOptionIndex ?? 0;
      } else if (imageAnswerType == 'subjective') {
        if (expectedAnswer != null && expectedAnswer!.trim().isNotEmpty) {
          map['expectedAnswer'] = expectedAnswer;
        }
        if (keywords != null && keywords!.isNotEmpty) {
          final normalized = keywords!
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList();
          if (normalized.isNotEmpty) {
            map['keywords'] = normalized;
          }
        }
      }
    }

    for (final entry in extraFields.entries) {
      if (!map.containsKey(entry.key)) {
        map[entry.key] = entry.value;
      }
    }

    return map;
  }

  // Create from Map (Firebase data)
  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    final rawExtra = <String, dynamic>{};
    const knownKeys = <String>{
      'id',
      'type',
      'question',
      'imageUrl',
      'options',
      'correct',
      'language',
      'testCases',
      'expectedOutput',
      'solutionCode',
      'expectedAnswer',
      'keywords',
      'imageQuestionContent',
      'imageAnswerType',
    };

    map.forEach((rawKey, value) {
      final key = rawKey.toString();
      if (!knownKeys.contains(key)) {
        rawExtra[key] = value;
      }
    });

    final typeStr = map['type'] as String?;
    final type = switch (typeStr) {
      'coding' => QuestionType.coding,
      'subjective' => QuestionType.subjective,
      'image' => QuestionType.image,
      _ => QuestionType.mcq,
    };

    final String? imageUrl = map['imageUrl']?.toString();

    if (type == QuestionType.mcq) {
      return QuizQuestion(
        id: map['id'] ?? '',
        type: QuestionType.mcq,
        question: map['question'] ?? '',
        imageUrl: imageUrl,
        options: List<String>.from(map['options'] ?? const []),
        correctOptionIndex: map['correct'] ?? 0,
        extraFields: rawExtra,
      );
    } else if (type == QuestionType.subjective) {
      return QuizQuestion(
        id: map['id'] ?? '',
        type: QuestionType.subjective,
        question: map['question'] ?? '',
        imageUrl: imageUrl,
        expectedAnswer: map['expectedAnswer']?.toString(),
        keywords: (map['keywords'] as List<dynamic>?)
            ?.map((k) => k.toString())
            .toList(),
        extraFields: rawExtra,
      );
    } else if (type == QuestionType.image) {
      final imageAnswerType = map['imageAnswerType'] as String? ?? 'subjective';
      final String? imageQuestionContent = map['imageQuestionContent']?.toString();

      if (imageAnswerType == 'mcq') {
        return QuizQuestion(
          id: map['id'] ?? '',
          type: QuestionType.image,
          question: map['question'] ?? '',
          imageQuestionContent: imageQuestionContent ?? '',
          imageAnswerType: 'mcq',
          options: List<String>.from(map['options'] ?? const []),
          correctOptionIndex: map['correct'] ?? 0,
          extraFields: rawExtra,
        );
      } else {
        return QuizQuestion(
          id: map['id'] ?? '',
          type: QuestionType.image,
          question: map['question'] ?? '',
          imageQuestionContent: imageQuestionContent ?? '',
          imageAnswerType: 'subjective',
          expectedAnswer: map['expectedAnswer']?.toString(),
          keywords: (map['keywords'] as List<dynamic>?)
              ?.map((k) => k.toString())
              .toList(),
          extraFields: rawExtra,
        );
      }
    } else {
      final langStr = map['language'] as String?;
      ProgrammingLanguage lang = ProgrammingLanguage.python;
      if (langStr != null) {
        try {
          lang = ProgrammingLanguage.values.firstWhere(
            (e) => e.name == langStr,
            orElse: () => ProgrammingLanguage.python,
          );
        } catch (_) {
          lang = ProgrammingLanguage.python;
        }
      }

      return QuizQuestion(
        id: map['id'] ?? '',
        type: QuestionType.coding,
        question: map['question'] ?? '',
        imageUrl: imageUrl,
        language: lang,
        testCases: (map['testCases'] as List<dynamic>?)
            ?.map((tc) => TestCase.fromMap(tc as Map<String, dynamic>))
            .toList(),
        expectedOutput: map['expectedOutput'],
        solutionCode: map['solutionCode'],
        extraFields: rawExtra,
      );
    }
  }
}

class TestCase {
  final String input;
  final String expectedOutput;
  final bool isHidden; // Hidden test cases not shown to students
  final String? description;

  TestCase({
    required this.input,
    required this.expectedOutput,
    this.isHidden = false,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'input': input,
      'expectedOutput': expectedOutput,
      'isHidden': isHidden,
      'description': description,
    };
  }

  factory TestCase.fromMap(Map<String, dynamic> map) {
    return TestCase(
      input: map['input'] ?? '',
      expectedOutput: map['expectedOutput'] ?? '',
      isHidden: map['isHidden'] ?? false,
      description: map['description'],
    );
  }
}

// Helper function to get language display name
String getLanguageDisplayName(ProgrammingLanguage lang) {
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

// Helper function to get file extension for language
String getLanguageExtension(ProgrammingLanguage lang) {
  switch (lang) {
    case ProgrammingLanguage.python:
      return '.py';
    case ProgrammingLanguage.java:
      return '.java';
    case ProgrammingLanguage.cpp:
      return '.cpp';
    case ProgrammingLanguage.javascript:
      return '.js';
    case ProgrammingLanguage.dart:
      return '.dart';
  }
}
