import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/models/assessment_tagging.dart';
import 'package:stela_app/models/quiz_model.dart';

void main() {
  group('Assessment tagging models', () {
    test('QuizQuestion preserves future fields during round-trip serialization', () {
      final original = {
        'id': 'q-1',
        'type': 'mcq',
        'question': 'What is 2 + 2?',
        'options': ['3', '4', '5'],
        'correct': 1,
        'suggestedSkills': ['arithmetic'],
        'unknownField': {'keep': true},
      };

      final question = QuizQuestion.fromMap(original);
      final roundTrip = QuizQuestion.fromMap(question.toMap());

      expect(roundTrip.id, 'q-1');
      expect(roundTrip.extraFields['unknownField'], {'keep': true});
      expect(roundTrip.toMap()['suggestedSkills'], isNotNull);
    });

    test('QuestionTagMetadata round-trips with additive metadata', () {
      final metadata = QuestionTagMetadata(
        quizId: 'quiz-17',
        questionId: 'q-1',
        stableQuestionId: 'stable-1',
        conceptIds: ['concept-1', 'concept-2'],
        primaryConceptId: 'concept-1',
        assessedSkillIds: ['skill-1'],
        suggestedSkillIds: ['skill-2'],
        reviewed: true,
      );

      final roundTrip = QuestionTagMetadata.fromMap(metadata.toMap());

      expect(roundTrip.quizId, 'quiz-17');
      expect(roundTrip.primaryConceptId, 'concept-1');
      expect(roundTrip.assessedSkillIds, ['skill-1']);
      expect(roundTrip.sidecarPath, 'question_tagging/quiz-17/q-1');
    });

    test('Evidence summarizer deduplicates repeated question contributions', () {
      final summary = AssessmentEvidenceAggregator.summarize([
        const QuestionEvidenceEntry(questionId: 'q-1', conceptId: 'c-1', earnedMarks: 1, possibleMarks: 2),
        const QuestionEvidenceEntry(questionId: 'q-1', conceptId: 'c-1', earnedMarks: 1, possibleMarks: 2),
        const QuestionEvidenceEntry(questionId: 'q-2', conceptId: 'c-1', earnedMarks: 2, possibleMarks: 4),
      ]);

      expect(summary.earnedMarks, 4);
      expect(summary.possibleMarks, 8);
      expect(summary.distinctQuestionCount, 2);
      expect(summary.ratio, closeTo(0.5, 0.0001));
    });
  });
}
