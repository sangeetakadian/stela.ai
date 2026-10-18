import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/services/assessment_tagging_service.dart';

void main() {
  group('AssessmentTaggingService', () {
    test('question fingerprints are stable for the same question content', () {
      final question = {
        'id': 'q-1',
        'type': 'mcq',
        'question': 'What is 2 + 2?',
        'options': ['3', '4', '5', '6'],
        'correct': 1,
      };

      final fingerprintA =
          AssessmentTaggingService.buildQuestionFingerprint(question);
      final fingerprintB = AssessmentTaggingService.buildQuestionFingerprint(
          Map<String, dynamic>.from(question));

      expect(fingerprintA, isNotEmpty);
      expect(fingerprintA, fingerprintB);
    });

    test('question fingerprint changes when the prompt changes', () {
      final first = {
        'id': 'q-1',
        'type': 'mcq',
        'question': 'What is 2 + 2?',
        'options': ['3', '4', '5', '6'],
        'correct': 1,
      };
      final second = {
        'id': 'q-1',
        'type': 'mcq',
        'question': 'What is 2 + 3?',
        'options': ['3', '4', '5', '6'],
        'correct': 1,
      };

      expect(
        AssessmentTaggingService.buildQuestionFingerprint(first),
        isNot(AssessmentTaggingService.buildQuestionFingerprint(second)),
      );
    });

    test('fingerprint covers marks, ordered options and nested coding criteria',
        () {
      final original = {
        'type': 'coding',
        'question': 'Write a function',
        'marks': 5,
        'testCases': [
          {'input': '1', 'expectedOutput': '2'},
        ],
        'assessmentTag': {
          'conceptIds': ['c-1']
        },
      };
      final changed = {
        'type': 'coding',
        'question': 'Write a function',
        'marks': 5,
        'testCases': [
          {'input': '1', 'expectedOutput': '3'},
        ],
        'assessmentTag': {
          'conceptIds': ['c-2']
        },
      };

      expect(
        AssessmentTaggingService.buildQuestionFingerprint(original),
        isNot(AssessmentTaggingService.buildQuestionFingerprint(changed)),
      );
      expect(
        AssessmentTaggingService.buildQuestionFingerprint(original),
        startsWith('qfp2_'),
      );
    });

    test('fingerprint ignores tag metadata and payload preserves future fields',
        () {
      final question = {
        'type': 'mcq',
        'question': 'Prompt',
        'options': ['A', 'B'],
        'assessmentTag': {
          'conceptIds': ['c-1']
        },
      };
      final sameQuestionWithOtherTags = {
        ...question,
        'assessmentTag': {
          'conceptIds': ['c-2']
        },
      };
      final payload = AssessmentTaggingService.safeTagPayload({
        'unknownFutureValue': {'keep': true},
        'proposedSkillIds': ['skill-proposed'],
      });

      expect(
        AssessmentTaggingService.buildQuestionFingerprint(question),
        AssessmentTaggingService.buildQuestionFingerprint(
          sameQuestionWithOtherTags,
        ),
      );
      expect(payload['unknownFutureValue'], {'keep': true});
      expect(payload['proposedSkillIds'], ['skill-proposed']);
    });

    test('question IDs are made safe for Firebase child paths', () {
      final unsafeQuestion = {'id': 'legacy/question.1'};
      final pathId =
          AssessmentTaggingService.questionIdForIndex(unsafeQuestion, 0);

      expect(pathId, isNot(contains('/')));
      expect(pathId, isNot(contains('.')));
      expect(pathId, startsWith('question_'));
    });
  });
}
