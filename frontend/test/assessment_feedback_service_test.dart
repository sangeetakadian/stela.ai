import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/models/assessment_tagging.dart';
import 'package:stela_app/services/assessment_feedback_service.dart';
import 'package:stela_app/services/assessment_tagging_service.dart';
import 'package:stela_app/services/taxonomy_service.dart';

Map<String, dynamic> _taggedQuestion(String id, {bool reviewed = true}) {
  final question = <String, dynamic>{
    'id': id,
    'type': 'mcq',
    'question': 'Prompt $id',
    'options': ['A', 'B'],
    'correct': 0,
  };
  question['assessmentTag'] = {
    'conceptIds': ['concept-primary', 'concept-related'],
    'conceptLabels': {
      'concept-primary': 'Digital Electronics / Flip-Flops',
      'concept-related': 'Digital Electronics',
    },
    'primaryConceptId': 'concept-primary',
    'assessedSkillIds': ['skill-reasoning'],
    'skillLabels': {'skill-reasoning': 'Apply engineering reasoning'},
    'reviewed': reviewed,
    'sourceFingerprint':
        AssessmentTaggingService.buildQuestionFingerprint(question),
    'stableQuestionId': 'stable-$id',
  };
  return question;
}

void main() {
  group('AssessmentFeedbackService', () {
    test('uses reviewed primary concept and explicitly assessed skills only',
        () {
      final questions = [_taggedQuestion('q1')];
      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: questions,
        earnedMarksByQuestion: [1],
        possibleMarksByQuestion: [2],
      );

      expect(feedback.map((item) => item.id),
          ['concept-primary', 'skill-reasoning']);
      expect(feedback.first.label, 'Digital Electronics / Flip-Flops');
      expect(feedback.last.label, 'Apply engineering reasoning');
      expect(feedback.first.status, 'Based on this quiz');
      expect(feedback.first.ratio, 0.5);
      expect(feedback.last.status, 'Insufficient evidence');
      expect(feedback.last.distinctQuestionCount, 1);
    });

    test('skill score is withheld until five distinct reviewed items', () {
      final questions = List.generate(5, (index) => _taggedQuestion('q$index'));
      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: questions,
        earnedMarksByQuestion: [1, 0, 1, 0, 1],
        possibleMarksByQuestion: [1, 1, 1, 1, 1],
      );

      final skill =
          feedback.singleWhere((item) => item.id == 'skill-reasoning');
      expect(skill.status, 'Based on this quiz');
      expect(skill.distinctQuestionCount, 5);
      expect(skill.ratio, 0.6);
    });

    test('unreviewed, stale and identity-mismatched tags do not contribute',
        () {
      final unreviewed = _taggedQuestion('q1', reviewed: false);
      final stale = _taggedQuestion('q2')..['assessmentTagStale'] = true;
      final mismatched = _taggedQuestion('q3');
      (mismatched['assessmentTag']
          as Map<String, dynamic>)['sourceFingerprint'] = 'old-fingerprint';

      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: [unreviewed, stale, mismatched],
        earnedMarksByQuestion: [1, 1, 1],
        possibleMarksByQuestion: [1, 1, 1],
      );

      expect(feedback, isEmpty);
    });

    test('ambiguous duplicate question identities are excluded', () {
      final first = _taggedQuestion('same-id');
      final second = _taggedQuestion('same-id');
      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: [first, second],
        earnedMarksByQuestion: [1, 0],
        possibleMarksByQuestion: [1, 1],
      );

      expect(feedback, isEmpty);
    });

    test('concept parent roll-up counts a question once across sibling tags',
        () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'parent',
        kind: TaxonomyNodeKind.concept,
        name: 'Parent concept',
      );
      registry.createNode(
        id: 'child-1',
        kind: TaxonomyNodeKind.concept,
        name: 'Child one',
        parentId: 'parent',
      );
      registry.createNode(
        id: 'child-2',
        kind: TaxonomyNodeKind.concept,
        name: 'Child two',
        parentId: 'parent',
      );
      final question = _taggedQuestion('q1');
      final tag = question['assessmentTag'] as Map<String, dynamic>;
      tag['conceptIds'] = ['child-1', 'child-2'];
      tag.remove('primaryConceptId');

      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: [question],
        earnedMarksByQuestion: [1],
        possibleMarksByQuestion: [2],
        taxonomyNodes: registry.nodes,
      );
      final parent = feedback.singleWhere((item) => item.id == 'parent');

      expect(parent.label, 'Parent concept');
      expect(parent.distinctQuestionCount, 1);
      expect(parent.earnedMarks, 1);
      expect(parent.possibleMarks, 2);

      final withoutTaxonomy = AssessmentFeedbackService.summarizeQuiz(
        questions: [question],
        earnedMarksByQuestion: [1],
        possibleMarksByQuestion: [2],
      );
      expect(
        withoutTaxonomy.any((item) => item.id == 'parent'),
        isFalse,
      );
    });

    test('missing score alignment or invalid denominators abstain', () {
      final feedback = AssessmentFeedbackService.summarizeQuiz(
        questions: [
          _taggedQuestion('q1'),
          _taggedQuestion('q2'),
          _taggedQuestion('q3'),
        ],
        earnedMarksByQuestion: [1, 2, 0],
        possibleMarksByQuestion: [1, 1, 0],
      );

      expect(feedback.map((item) => item.distinctQuestionCount), [1, 1]);
    });
  });
}
