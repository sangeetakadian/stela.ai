import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/models/assessment_tagging.dart';
import 'package:stela_app/services/taxonomy_service.dart';

TaxonomyRegistry _exampleRegistry() {
  final registry = TaxonomyRegistry();
  registry.createNode(
    id: 'concept_digital_electronics',
    kind: TaxonomyNodeKind.concept,
    name: 'Digital Electronics',
  );
  registry.createNode(
    id: 'concept_sequential_circuits',
    kind: TaxonomyNodeKind.concept,
    name: 'Sequential Circuits',
    parentId: 'concept_digital_electronics',
  );
  registry.createNode(
    id: 'concept_flip_flops',
    kind: TaxonomyNodeKind.concept,
    name: 'Flip-Flops',
    parentId: 'concept_sequential_circuits',
  );
  registry.createNode(
    id: 'skill_apply_boolean_logic',
    kind: TaxonomyNodeKind.skill,
    name: 'Apply Boolean logic',
  );
  return registry;
}

void main() {
  group('TaxonomyService', () {
    test('rejects blank node names', () {
      expect(TaxonomyService.validateNodeName('   '), isNotNull);
      expect(TaxonomyService.validateNodeName('Digital Logic'), isNull);
    });

    test('builds breadcrumbs from ancestry', () {
      final nodes = {
        'root': const TaxonomyNode(
          id: 'root',
          kind: TaxonomyNodeKind.concept,
          name: 'Digital Electronics',
        ),
        'sequential': TaxonomyNode(
          id: 'sequential',
          kind: TaxonomyNodeKind.concept,
          name: 'Sequential Circuits',
          parentId: 'root',
        ),
        'flipflop': TaxonomyNode(
          id: 'flipflop',
          kind: TaxonomyNodeKind.concept,
          name: 'Flip-Flops',
          parentId: 'sequential',
        ),
      };

      expect(
        TaxonomyService.buildBreadcrumb(nodes: nodes, nodeId: 'flipflop'),
        'Digital Electronics / Sequential Circuits / Flip-Flops',
      );
    });

    test('detects duplicate sibling names', () {
      final nodes = {
        'parent': const TaxonomyNode(
          id: 'parent',
          kind: TaxonomyNodeKind.concept,
          name: 'Core Topics',
        ),
        'existing': TaxonomyNode(
          id: 'existing',
          kind: TaxonomyNodeKind.concept,
          name: 'Logic Gates',
          parentId: 'parent',
        ),
      };

      expect(
        TaxonomyService.hasDuplicateSiblingName(
          name: 'Logic Gates',
          parentId: 'parent',
          nodes: nodes,
          excludeNodeId: null,
        ),
        isTrue,
      );
    });

    test('prevents cycle when reparenting', () {
      final nodes = {
        'a': const TaxonomyNode(
          id: 'a',
          kind: TaxonomyNodeKind.concept,
          name: 'A',
        ),
        'b': TaxonomyNode(
          id: 'b',
          kind: TaxonomyNodeKind.concept,
          name: 'B',
          parentId: 'a',
        ),
      };

      expect(
        () => TaxonomyService.reparentNode(
          nodes: nodes,
          nodeId: 'a',
          newParentId: 'b',
          requiredKind: TaxonomyNodeKind.concept,
        ),
        throwsArgumentError,
      );
    });

    test('allows valid parent assignment across same-kind nodes', () {
      final nodes = {
        'root': const TaxonomyNode(
          id: 'root',
          kind: TaxonomyNodeKind.concept,
          name: 'Root',
        ),
        'child': TaxonomyNode(
          id: 'child',
          kind: TaxonomyNodeKind.concept,
          name: 'Child',
          parentId: 'root',
        ),
      };

      expect(
        TaxonomyService.isValidParentAssignment(
          parentId: 'root',
          candidateId: 'child',
          nodes: nodes,
          requiredKind: TaxonomyNodeKind.concept,
        ),
        isTrue,
      );
    });

    test('registry creates nodes with validation and search support', () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'root',
        kind: TaxonomyNodeKind.concept,
        name: 'Digital Electronics',
      );
      registry.createNode(
        id: 'sequential',
        kind: TaxonomyNodeKind.concept,
        name: 'Sequential Circuits',
        parentId: 'root',
      );
      registry.createNode(
        id: 'skill_apply',
        kind: TaxonomyNodeKind.skill,
        name: 'Apply Logic',
      );

      expect(
        registry.search('sequential').first.path,
        'Digital Electronics / Sequential Circuits',
      );
      expect(registry.childrenOf('root').length, 1);
      expect(registry.nodes['skill_apply']!.kind, TaxonomyNodeKind.skill);
    });

    test(
        'registry rejects duplicate sibling names and archived nodes are hidden from active search',
        () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'root',
        kind: TaxonomyNodeKind.concept,
        name: 'Core Topics',
      );
      registry.createNode(
        id: 'first',
        kind: TaxonomyNodeKind.concept,
        name: 'Logic Gates',
        parentId: 'root',
      );

      expect(
        () => registry.createNode(
          id: 'second',
          kind: TaxonomyNodeKind.concept,
          name: 'Logic Gates',
          parentId: 'root',
        ),
        throwsArgumentError,
      );

      registry.archiveNode('first');
      expect(registry.search('logic').isEmpty, isTrue);
    });

    test(
        'registry exposes searchable concepts and skills for the faculty workflow',
        () {
      final registry = _exampleRegistry();

      expect(registry.nodes.containsKey('concept_digital_electronics'), isTrue);
      expect(registry.nodes.containsKey('skill_apply_boolean_logic'), isTrue);
      expect(registry.search('flip').first.path,
          'Digital Electronics / Sequential Circuits / Flip-Flops');
      expect(registry.search('logic', kind: TaxonomyNodeKind.skill).first.name,
          'Apply Boolean logic');
      expect(registry.activeNodesByKind(TaxonomyNodeKind.skill).length,
          greaterThanOrEqualTo(1));
    });

    test('registry can serialize and restore a Firebase-compatible node map',
        () {
      final registry = _exampleRegistry();
      final encoded = registry.toFirebaseMap();
      final restored = TaxonomyRegistry.fromFirebaseMap(encoded);

      expect(restored.nodes.length, registry.nodes.length);
      expect(restored.search('flip').first.path,
          'Digital Electronics / Sequential Circuits / Flip-Flops');
      expect(restored.nodes['skill_apply_boolean_logic']!.kind,
          TaxonomyNodeKind.skill);
    });

    test('sibling uniqueness normalizes case and whitespace within scope', () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'shared-first',
        kind: TaxonomyNodeKind.concept,
        name: ' Logic   Gates ',
      );

      expect(
        () => registry.createNode(
          id: 'shared-duplicate',
          kind: TaxonomyNodeKind.concept,
          name: 'logic gates',
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.createNode(
          id: 'course-specific',
          kind: TaxonomyNodeKind.concept,
          name: 'Logic Gates',
          scope: 'course',
          courseId: 'course-1',
        ),
        returnsNormally,
      );
    });

    test('reparent rejects duplicate sibling names in the destination', () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'root-a',
        kind: TaxonomyNodeKind.concept,
        name: 'A',
      );
      registry.createNode(
        id: 'root-b',
        kind: TaxonomyNodeKind.concept,
        name: 'B',
      );
      registry.createNode(
        id: 'first',
        kind: TaxonomyNodeKind.concept,
        name: 'Same name',
        parentId: 'root-b',
      );
      registry.createNode(
        id: 'moving',
        kind: TaxonomyNodeKind.concept,
        name: 'Same name',
        parentId: 'root-a',
      );

      expect(
        () => registry.reparentNode(
          nodeId: 'moving',
          newParentId: 'root-b',
          requiredKind: TaxonomyNodeKind.concept,
        ),
        throwsArgumentError,
      );
    });

    test('reparenting to a root clears the parent while preserving the node ID',
        () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'root',
        kind: TaxonomyNodeKind.concept,
        name: 'Root',
      );
      registry.createNode(
        id: 'child',
        kind: TaxonomyNodeKind.concept,
        name: 'Child',
        parentId: 'root',
      );

      registry.reparentNode(
        nodeId: 'child',
        newParentId: null,
        requiredKind: TaxonomyNodeKind.concept,
      );

      expect(registry.nodes['child']!.id, 'child');
      expect(registry.nodes['child']!.parentId, isNull);
      expect(
        TaxonomyService.buildBreadcrumb(nodes: registry.nodes, nodeId: 'child'),
        'Child',
      );
    });

    test('course-specific results are prioritized without hiding shared nodes',
        () {
      final registry = TaxonomyRegistry();
      registry.createNode(
        id: 'shared',
        kind: TaxonomyNodeKind.concept,
        name: 'Logic',
      );
      registry.createNode(
        id: 'course',
        kind: TaxonomyNodeKind.concept,
        name: 'Logic',
        scope: 'course',
        courseId: 'course-1',
      );

      final results = registry.search('logic', courseId: 'course-1');

      expect(results.map((result) => result.nodeId), ['course', 'shared']);
    });
  });
}
