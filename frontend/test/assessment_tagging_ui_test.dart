import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/models/assessment_tagging.dart';
import 'package:stela_app/screens/quiz_results_screen.dart';
import 'package:stela_app/services/assessment_tagging_service.dart';
import 'package:stela_app/services/taxonomy_service.dart';
import 'package:stela_app/widgets/assessment_tag_editor.dart';

void main() {
  testWidgets('faculty can select and reconfirm question tags',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final registry = TaxonomyRegistry(
      initialNodes: {
        'mathematics': const TaxonomyNode(
          id: 'mathematics',
          kind: TaxonomyNodeKind.concept,
          name: 'Mathematics',
        ),
        'algebra': const TaxonomyNode(
          id: 'algebra',
          kind: TaxonomyNodeKind.concept,
          name: 'Algebra',
          parentId: 'mathematics',
        ),
        'reasoning': const TaxonomyNode(
          id: 'reasoning',
          kind: TaxonomyNodeKind.skill,
          name: 'Reasoning',
        ),
      },
    );
    Map<String, dynamic>? savedTag;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                savedTag = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => AssessmentTagEditorDialog(
                    taxonomyRegistry: registry,
                    sourceIsStale: true,
                  ),
                );
              },
              child: const Text('Tag concepts & skills'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tag concepts & skills'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The question changed since these tags were last reviewed. Confirm the mapping again before saving.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reconfirm tags'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Mathematics / Algebra'));
    await tester.tap(find.widgetWithText(FilterChip, 'Reasoning'));
    await tester.tap(find.text('Reconfirm tags'));
    await tester.pumpAndSettle();

    expect(savedTag?['conceptIds'], ['algebra']);
    expect(savedTag?['primaryConceptId'], 'algebra');
    expect(savedTag?['assessedSkillIds'], ['reasoning']);
    expect(savedTag?['reviewed'], isTrue);
    expect(savedTag?['suggestedSkillIds'], isEmpty);
  });

  testWidgets('student results show current question-level evidence',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final question = <String, dynamic>{
      'question': 'Solve the equation.',
      'type': 'mcq',
      'options': ['x = 2', 'x = 3'],
      'correct': 0,
    };
    final fingerprint =
        AssessmentTaggingService.buildQuestionFingerprint(question);
    question['assessmentTag'] = {
      'reviewed': true,
      'sourceFingerprint': fingerprint,
      'conceptIds': ['algebra'],
      'conceptLabels': {'algebra': 'Mathematics / Algebra'},
      'assessedSkillIds': ['reasoning'],
      'skillLabels': {'reasoning': 'Reasoning'},
      'suggestedSkillIds': ['unconfirmed'],
      'skillSuggestionLabels': {'unconfirmed': 'Unconfirmed skill'},
    };
    question['assessmentTagSourceFingerprint'] = fingerprint;

    await tester.pumpWidget(
      MaterialApp(
        home: QuizResultsScreen(
          quiz: const {'title': 'Algebra quiz'},
          subject: const {'label': 'Mathematics', 'color': Colors.blue},
          questions: [question],
          userAnswers: const [0],
          correctAnswers: 1,
          percentage: 100,
          timeTaken: Duration.zero,
          earnedMarksByQuestion: const [1],
          possibleMarksByQuestion: const [1],
          taxonomyNodes: const {
            'mathematics': TaxonomyNode(
              id: 'mathematics',
              kind: TaxonomyNodeKind.concept,
              name: 'Mathematics',
            ),
            'algebra': TaxonomyNode(
              id: 'algebra',
              kind: TaxonomyNodeKind.concept,
              name: 'Algebra',
              parentId: 'mathematics',
            ),
            'reasoning': TaxonomyNode(
              id: 'reasoning',
              kind: TaxonomyNodeKind.skill,
              name: 'Reasoning',
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Question-level evidence'));

    expect(find.text('Concept: Mathematics / Algebra'), findsOneWidget);
    expect(find.text('Concept: Mathematics'), findsOneWidget);
    expect(find.text('1/1 (100%) • 1 item(s)'), findsNWidgets(2));
    expect(find.text('Skill: Reasoning'), findsOneWidget);
    expect(find.textContaining('Insufficient evidence'), findsOneWidget);
    expect(find.text('Concepts: Mathematics / Algebra'), findsOneWidget);
    expect(find.text('Skills: Reasoning'), findsOneWidget);
    expect(find.text('Score: 1/1 marks'), findsOneWidget);
    expect(find.textContaining('Unconfirmed skill'), findsNothing);
  });

  testWidgets('student results explain when tag metadata cannot be loaded',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: QuizResultsScreen(
          quiz: const {'title': 'Algebra quiz'},
          subject: const {'label': 'Mathematics', 'color': Colors.blue},
          questions: const [
            {'question': 'Solve the equation.', 'type': 'mcq'},
          ],
          userAnswers: const [null],
          correctAnswers: 0,
          percentage: 0,
          timeTaken: Duration.zero,
          assessmentTagsLoadFailed: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Check student read access'),
      findsOneWidget,
    );
    expect(
      find.text('Question-level evidence: Tag data could not be loaded'),
      findsOneWidget,
    );
  });
}
