import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';

class AssessmentTaggingService {
  static DatabaseReference get _rootRef =>
      FirebaseDatabase.instance.ref().child('question_tagging');

  static Map<String, dynamic>? extractTag(Map<String, dynamic> question) {
    final raw = question['assessmentTag'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  static List<Map<String, dynamic>> stripTagFields(List<dynamic> questions) {
    final cleaned = <Map<String, dynamic>>[];
    for (final entry in questions) {
      if (entry is Map) {
        final clean = Map<String, dynamic>.from(entry);
        clean.remove('assessmentTag');
        if (clean.isNotEmpty) {
          cleaned.add(clean);
        }
      }
    }
    return cleaned;
  }

  static String buildQuestionFingerprint(Map<String, dynamic> question) {
    final payload = jsonEncode(_canonicalQuestionValue(question, root: true));
    final bytes = utf8.encode(payload);
    var hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash *= 16777619;
      hash &= 0xffffffff;
    }

    return 'qfp2_${hash.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';
  }

  static dynamic _canonicalQuestionValue(dynamic value, {bool root = false}) {
    if (value is Map) {
      final entries = value.entries
          .where((entry) =>
              !root ||
              !const {
                'id',
                'questionId',
                'stableQuestionId',
                'assessmentTag',
                'assessmentTagStale',
                'assessmentTagSourceFingerprint',
              }.contains(entry.key.toString()))
          .toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, dynamic>{
        for (final entry in entries)
          entry.key.toString(): _canonicalQuestionValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalQuestionValue).toList(growable: false);
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    return value;
  }

  static String questionIdForIndex(Map<String, dynamic> question, int index) {
    final rawId = question['id'] ?? question['questionId'];
    if (rawId != null && rawId.toString().trim().isNotEmpty) {
      final id = rawId.toString();
      if (RegExp(r'[.#$\[\]/\u0000-\u001F\u007F]').hasMatch(id)) {
        return 'question_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
      }
      return id;
    }
    return 'question_${index + 1}';
  }

  static String stableQuestionIdForIndex(
      Map<String, dynamic> question, int index) {
    final explicit = question['stableQuestionId'];
    if (explicit != null && explicit.toString().trim().isNotEmpty) {
      return explicit.toString();
    }
    return '${questionIdForIndex(question, index)}_${buildQuestionFingerprint(question)}';
  }

  static Map<String, dynamic> safeTagPayload(Map<String, dynamic> tag) {
    final payload = <String, dynamic>{
      for (final entry in tag.entries)
        if (!const {
          'conceptIds',
          'conceptLabels',
          'primaryConceptId',
          'assessedSkillIds',
          'skillLabels',
          'suggestedSkillIds',
          'proposedSkillIds',
          'reviewed',
          'updatedAt',
          'sourceFingerprint',
          'stableQuestionId',
          'quizId',
          'questionId',
        }.contains(entry.key))
          entry.key: entry.value,
      'conceptIds': tag['conceptIds'] ?? const <String>[],
      'conceptLabels': tag['conceptLabels'] ?? const <String, String>{},
      'primaryConceptId': tag['primaryConceptId'],
      'assessedSkillIds': tag['assessedSkillIds'] ?? const <String>[],
      'skillLabels': tag['skillLabels'] ?? const <String, String>{},
      'suggestedSkillIds': tag['suggestedSkillIds'] ?? const <String>[],
      'proposedSkillIds': tag['proposedSkillIds'] ?? const <String>[],
      'reviewed': tag['reviewed'] ?? true,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    if (tag['sourceFingerprint'] != null &&
        tag['sourceFingerprint'].toString().trim().isNotEmpty) {
      payload['sourceFingerprint'] = tag['sourceFingerprint'].toString();
    }

    return payload;
  }

  static Future<void> persistQuizQuestionTags({
    required String subjectKey,
    required String quizId,
    required List<Map<String, dynamic>> questions,
  }) async {
    for (var i = 0; i < questions.length; i++) {
      final question = questions[i];
      final tag = extractTag(question);
      if (tag == null ||
          tag.isEmpty ||
          question['assessmentTagStale'] == true) {
        continue;
      }

      final questionId = questionIdForIndex(question, i);
      final stableQuestionId = stableQuestionIdForIndex(question, i);
      final payload = safeTagPayload({
        ...tag,
        'sourceFingerprint': buildQuestionFingerprint(question),
      });

      await _rootRef.child(subjectKey).child(quizId).child(questionId).set({
        ...payload,
        'stableQuestionId': stableQuestionId,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> loadQuizQuestionTags({
    required String subjectKey,
    required String quizId,
    required List<Map<String, dynamic>> questions,
    DatabaseReference? ref,
  }) async {
    final rootRef = ref ?? _rootRef;
    return Future.wait(List.generate(questions.length, (index) async {
      final question = Map<String, dynamic>.from(questions[index]);
      final questionId = questionIdForIndex(question, index);
      final snapshot =
          await rootRef.child(subjectKey).child(quizId).child(questionId).get();
      final rawTag = snapshot.value;

      if (!snapshot.exists) {
        return question;
      }
      if (rawTag is! Map) {
        throw FormatException(
          'Question-tagging metadata for $questionId is not a map.',
        );
      }

      final tag = Map<String, dynamic>.from(rawTag);
      final expectedFingerprint = tag['sourceFingerprint']?.toString();
      final actualFingerprint = buildQuestionFingerprint(question);
      question['assessmentTagStale'] = expectedFingerprint == null ||
          expectedFingerprint.isEmpty ||
          expectedFingerprint != actualFingerprint;
      question['assessmentTagSourceFingerprint'] = actualFingerprint;
      question['assessmentTag'] = tag;
      return question;
    }));
  }
}
