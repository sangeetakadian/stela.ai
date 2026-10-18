import '../models/assessment_tagging.dart';
import 'assessment_tagging_service.dart';
import 'taxonomy_service.dart';

class AssessmentFeedbackItem {
  const AssessmentFeedbackItem({
    required this.id,
    required this.label,
    required this.kind,
    required this.earnedMarks,
    required this.possibleMarks,
    required this.distinctQuestionCount,
    required this.status,
  });

  final String id;
  final String label;
  final TaxonomyNodeKind kind;
  final double earnedMarks;
  final double possibleMarks;
  final int distinctQuestionCount;
  final String status;

  double get ratio => possibleMarks <= 0 ? 0 : earnedMarks / possibleMarks;
}

class AssessmentFeedbackService {
  static List<AssessmentFeedbackItem> summarizeQuiz({
    required List<Map<String, dynamic>> questions,
    required List<double> earnedMarksByQuestion,
    required List<double> possibleMarksByQuestion,
    Map<String, TaxonomyNode> taxonomyNodes = const {},
    int minimumSkillEvidenceItems = 5,
  }) {
    final conceptEvidence = <String, Map<String, QuestionEvidenceEntry>>{};
    final skillEvidence = <String, Map<String, QuestionEvidenceEntry>>{};
    final ambiguousQuestionIds = <String>{};

    for (var index = 0; index < questions.length; index++) {
      if (index >= earnedMarksByQuestion.length ||
          index >= possibleMarksByQuestion.length) {
        continue;
      }

      final earned = earnedMarksByQuestion[index];
      final possible = possibleMarksByQuestion[index];
      if (!earned.isFinite ||
          !possible.isFinite ||
          possible <= 0 ||
          earned < 0 ||
          earned > possible) {
        continue;
      }

      final question = questions[index];
      final rawTag = question['assessmentTag'];
      if (rawTag is! Map) {
        continue;
      }
      final tag = Map<String, dynamic>.from(rawTag);
      if (tag['reviewed'] != true || question['assessmentTagStale'] == true) {
        continue;
      }

      final expectedFingerprint = tag['sourceFingerprint']?.toString();
      final actualFingerprint =
          question['assessmentTagSourceFingerprint']?.toString() ??
              AssessmentTaggingService.buildQuestionFingerprint(question);
      if (expectedFingerprint == null ||
          expectedFingerprint.isEmpty ||
          expectedFingerprint != actualFingerprint) {
        continue;
      }

      final questionId = tag['stableQuestionId']?.toString() ??
          question['stableQuestionId']?.toString() ??
          AssessmentTaggingService.stableQuestionIdForIndex(question, index);
      if (ambiguousQuestionIds.contains(questionId)) {
        continue;
      }
      final alreadyCounted = conceptEvidence.values
              .any((items) => items.containsKey(questionId)) ||
          skillEvidence.values.any((items) => items.containsKey(questionId));
      if (alreadyCounted) {
        _removeQuestionEvidence(conceptEvidence, questionId);
        _removeQuestionEvidence(skillEvidence, questionId);
        ambiguousQuestionIds.add(questionId);
        continue;
      }
      final conceptIds = _stringSet(tag['conceptIds']);
      final primaryId = tag['primaryConceptId']?.toString();
      final directlyAssessedConcepts =
          primaryId != null && conceptIds.contains(primaryId)
              ? <String>{primaryId}
              : conceptIds;

      final conceptsForQuestion = <String>{};
      for (final id in directlyAssessedConcepts) {
        if (taxonomyNodes[id]?.kind != TaxonomyNodeKind.concept) {
          conceptsForQuestion.add(id);
          continue;
        }
        conceptsForQuestion.add(id);
        conceptsForQuestion.addAll(TaxonomyService.findAncestorIds(
          nodes: taxonomyNodes,
          nodeId: id,
        ).where((ancestorId) =>
            taxonomyNodes[ancestorId]?.kind == TaxonomyNodeKind.concept));
      }
      for (final id in conceptsForQuestion) {
        conceptEvidence.putIfAbsent(id, () => {})[questionId] =
            QuestionEvidenceEntry(
          questionId: questionId,
          conceptId: id,
          earnedMarks: earned,
          possibleMarks: possible,
        );
      }

      for (final id in _stringSet(tag['assessedSkillIds'])) {
        skillEvidence.putIfAbsent(id, () => {})[questionId] =
            QuestionEvidenceEntry(
          questionId: questionId,
          skillId: id,
          earnedMarks: earned,
          possibleMarks: possible,
        );
      }
    }

    final result = <AssessmentFeedbackItem>[];
    _appendSummaries(
      result,
      conceptEvidence,
      TaxonomyNodeKind.concept,
      labelMaps: _labelMaps(questions, 'conceptLabels'),
      taxonomyNodes: taxonomyNodes,
      minimumEvidenceItems: 1,
    );
    _appendSummaries(
      result,
      skillEvidence,
      TaxonomyNodeKind.skill,
      labelMaps: _labelMaps(questions, 'skillLabels'),
      taxonomyNodes: const {},
      minimumEvidenceItems: minimumSkillEvidenceItems,
    );
    result.sort((a, b) {
      final kindOrder = a.kind.index.compareTo(b.kind.index);
      return kindOrder != 0
          ? kindOrder
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return result;
  }

  static void _removeQuestionEvidence(
    Map<String, Map<String, QuestionEvidenceEntry>> evidence,
    String questionId,
  ) {
    for (final items in evidence.values) {
      items.remove(questionId);
    }
  }

  static void _appendSummaries(
    List<AssessmentFeedbackItem> output,
    Map<String, Map<String, QuestionEvidenceEntry>> evidence,
    TaxonomyNodeKind kind, {
    required Map<String, String> labelMaps,
    required Map<String, TaxonomyNode> taxonomyNodes,
    required int minimumEvidenceItems,
  }) {
    for (final entry in evidence.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final items = entry.value.values.toList();
      final earned =
          items.fold<double>(0, (sum, item) => sum + item.earnedMarks);
      final possible =
          items.fold<double>(0, (sum, item) => sum + item.possibleMarks);
      final count = items.map((item) => item.questionId).toSet().length;
      final status = possible <= 0
          ? 'Not assessed'
          : count >= minimumEvidenceItems
              ? 'Based on this quiz'
              : 'Insufficient evidence';

      output.add(AssessmentFeedbackItem(
        id: entry.key,
        label: taxonomyNodes.containsKey(entry.key)
            ? TaxonomyService.buildBreadcrumb(
                nodes: taxonomyNodes,
                nodeId: entry.key,
              )
            : labelMaps[entry.key] ?? entry.key,
        kind: kind,
        earnedMarks: earned,
        possibleMarks: possible,
        distinctQuestionCount: count,
        status: status,
      ));
    }
  }

  static Map<String, String> _labelMaps(
    List<Map<String, dynamic>> questions,
    String field,
  ) {
    final labels = <String, String>{};
    for (final question in questions) {
      final rawTag = question['assessmentTag'];
      if (rawTag is! Map || rawTag[field] is! Map) {
        continue;
      }
      (rawTag[field] as Map).forEach((id, label) {
        final normalizedLabel = label.toString().trim();
        if (normalizedLabel.isNotEmpty) {
          labels[id.toString()] = normalizedLabel;
        }
      });
    }
    return labels;
  }

  static Set<String> _stringSet(dynamic value) {
    if (value is! List) {
      return <String>{};
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }
}
