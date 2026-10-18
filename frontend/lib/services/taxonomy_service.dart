import 'package:firebase_database/firebase_database.dart';

import '../models/assessment_tagging.dart';

class TaxonomyService {
  TaxonomyService();

  static String normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateNodeName(String? value) {
    final cleaned = normalizeName(value ?? '');
    if (cleaned.isEmpty) {
      return 'Node name is required.';
    }
    return null;
  }

  static bool isValidParentAssignment({
    required String? parentId,
    required String? candidateId,
    required Map<String, TaxonomyNode> nodes,
    required TaxonomyNodeKind requiredKind,
  }) {
    if (parentId == null || parentId.isEmpty) {
      return true;
    }

    final parent = nodes[parentId];
    if (parent == null) {
      return false;
    }

    if (parent.kind != requiredKind) {
      return false;
    }

    if (candidateId == parentId) {
      return false;
    }

    return !wouldCreateCycle(
        candidateId: candidateId, parentId: parentId, nodes: nodes);
  }

  static bool wouldCreateCycle({
    required String? candidateId,
    required String parentId,
    required Map<String, TaxonomyNode> nodes,
  }) {
    if (candidateId == null || candidateId.isEmpty) {
      return false;
    }

    if (candidateId == parentId) {
      return true;
    }

    var currentParentId = parentId;
    while (currentParentId.isNotEmpty) {
      final currentParent = nodes[currentParentId];
      if (currentParent == null) {
        break;
      }
      if (currentParent.id == candidateId) {
        return true;
      }
      currentParentId = currentParent.parentId ?? '';
    }

    return false;
  }

  static String buildBreadcrumb({
    required Map<String, TaxonomyNode> nodes,
    required String nodeId,
  }) {
    final node = nodes[nodeId];
    if (node == null) {
      return '';
    }

    final parts = <String>[];
    final visited = <String>{};
    String? currentId = nodeId;

    while (currentId != null &&
        currentId.isNotEmpty &&
        !visited.contains(currentId)) {
      visited.add(currentId);
      final currentNode = nodes[currentId];
      if (currentNode == null) {
        break;
      }
      parts.add(currentNode.name);
      currentId = currentNode.parentId;
    }

    return parts.reversed.join(' / ');
  }

  static List<String> findAncestorIds({
    required Map<String, TaxonomyNode> nodes,
    required String nodeId,
  }) {
    final ids = <String>[];
    String? currentId = nodes[nodeId]?.parentId;

    while (currentId != null && currentId.isNotEmpty) {
      final currentNode = nodes[currentId];
      if (currentNode == null) {
        break;
      }
      ids.add(currentId);
      currentId = currentNode.parentId;
    }

    return ids.reversed.toList();
  }

  static bool hasDuplicateSiblingName({
    required String name,
    required String? parentId,
    required Map<String, TaxonomyNode> nodes,
    required String? excludeNodeId,
    String scope = 'shared',
  }) {
    final normalized = normalizeName(name).toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    for (final node in nodes.values) {
      if (node.id == excludeNodeId) {
        continue;
      }
      if (node.parentId != parentId) {
        continue;
      }
      if (node.scope != scope) {
        continue;
      }
      if (normalizeName(node.name).toLowerCase() == normalized) {
        return true;
      }
    }

    return false;
  }

  static Map<String, TaxonomyNode> addNode({
    required Map<String, TaxonomyNode> nodes,
    required TaxonomyNode node,
  }) {
    final updated = Map<String, TaxonomyNode>.from(nodes);
    updated[node.id] = node;
    return updated;
  }

  static Map<String, TaxonomyNode> reparentNode({
    required Map<String, TaxonomyNode> nodes,
    required String nodeId,
    required String? newParentId,
    required TaxonomyNodeKind requiredKind,
  }) {
    final node = nodes[nodeId];
    if (node == null) {
      throw ArgumentError('Unknown node id: $nodeId');
    }

    if (!isValidParentAssignment(
      parentId: newParentId,
      candidateId: nodeId,
      nodes: nodes,
      requiredKind: requiredKind,
    )) {
      throw ArgumentError('Invalid parent assignment for node $nodeId');
    }

    final updated = Map<String, TaxonomyNode>.from(nodes);
    updated[nodeId] = node.copyWith(
      parentId: newParentId,
      clearParentId: newParentId == null,
    );
    return updated;
  }
}

class TaxonomyRegistry {
  TaxonomyRegistry({Map<String, TaxonomyNode>? initialNodes})
      : nodes = Map<String, TaxonomyNode>.from(initialNodes ?? const {});

  final Map<String, TaxonomyNode> nodes;

  List<TaxonomyNode> activeNodesByKind(TaxonomyNodeKind kind) {
    final values = nodes.values
        .where((node) =>
            node.kind == kind &&
            (node.status == null || node.status != 'archived'))
        .toList();
    values.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values;
  }

  Map<String, dynamic> toFirebaseMap() {
    final payload = <String, dynamic>{};
    for (final entry in nodes.entries) {
      payload[entry.key] = entry.value.toMap();
    }
    return payload;
  }

  static TaxonomyRegistry fromFirebaseMap(Map<dynamic, dynamic> data) {
    final decoded = <String, TaxonomyNode>{};
    for (final entry in data.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        decoded[key] = TaxonomyNode.fromMap(Map<String, dynamic>.from(value));
      }
    }
    return TaxonomyRegistry(initialNodes: decoded);
  }

  Future<void> persistToFirebase({
    required String subjectKey,
    DatabaseReference? ref,
  }) async {
    final databaseRef = ref ??
        FirebaseDatabase.instance.ref().child('taxonomy').child(subjectKey);
    await databaseRef.update(toFirebaseMap());
  }

  static Future<TaxonomyRegistry> loadFromFirebase({
    required String subjectKey,
    DatabaseReference? ref,
  }) async {
    final databaseRef = ref ??
        FirebaseDatabase.instance.ref().child('taxonomy').child(subjectKey);
    final snapshot = await databaseRef.get();
    if (!snapshot.exists || snapshot.value == null) {
      return TaxonomyRegistry();
    }

    final raw = snapshot.value;
    if (raw is Map) {
      return fromFirebaseMap(raw);
    }

    throw FormatException(
        'Taxonomy data at ${databaseRef.path} must be a map.');
  }

  TaxonomyNode createNode({
    required String id,
    required TaxonomyNodeKind kind,
    required String name,
    String? parentId,
    String scope = 'shared',
    String? courseId,
    String? definition,
    List<String> aliases = const [],
    String? status,
    List<String> courseAssociations = const [],
    Map<String, dynamic> extraFields = const {},
  }) {
    final validationMessage = TaxonomyService.validateNodeName(name);
    if (validationMessage != null) {
      throw ArgumentError(validationMessage);
    }

    if (nodes.containsKey(id)) {
      throw ArgumentError('Node id already exists: $id');
    }

    if (parentId != null &&
        parentId.isNotEmpty &&
        !nodes.containsKey(parentId)) {
      throw ArgumentError('Parent node not found: $parentId');
    }

    if (parentId != null && parentId.isNotEmpty) {
      final parent = nodes[parentId]!;
      if (parent.kind != kind) {
        throw ArgumentError(
            'Parent kind mismatch: parent is ${parent.kind.name}, child is ${kind.name}');
      }
    }

    if (TaxonomyService.hasDuplicateSiblingName(
      name: name,
      parentId: parentId,
      nodes: nodes,
      excludeNodeId: null,
      scope: scope,
    )) {
      throw ArgumentError(
          'Duplicate sibling name is not allowed within the same parent.');
    }

    if (!TaxonomyService.isValidParentAssignment(
      parentId: parentId,
      candidateId: id,
      nodes: nodes,
      requiredKind: kind,
    )) {
      throw ArgumentError('Invalid parent assignment for node $id.');
    }

    final node = TaxonomyNode(
      id: id,
      kind: kind,
      name: TaxonomyService.normalizeName(name),
      parentId: parentId,
      scope: scope,
      courseId: courseId,
      definition: definition,
      aliases: aliases,
      status: status ?? 'active',
      courseAssociations: courseAssociations,
      extraFields: Map<String, dynamic>.from(extraFields),
    );

    nodes[id] = node;
    return node;
  }

  TaxonomyNode renameNode(String nodeId, String newName) {
    final node = nodes[nodeId];
    if (node == null) {
      throw ArgumentError('Unknown node id: $nodeId');
    }

    final validationMessage = TaxonomyService.validateNodeName(newName);
    if (validationMessage != null) {
      throw ArgumentError(validationMessage);
    }

    if (TaxonomyService.hasDuplicateSiblingName(
      name: newName,
      parentId: node.parentId,
      nodes: nodes,
      excludeNodeId: nodeId,
      scope: node.scope,
    )) {
      throw ArgumentError('A sibling with the same name already exists.');
    }

    final renamed = node.copyWith(name: TaxonomyService.normalizeName(newName));
    nodes[nodeId] = renamed;
    return renamed;
  }

  TaxonomyNode reparentNode({
    required String nodeId,
    required String? newParentId,
    required TaxonomyNodeKind requiredKind,
  }) {
    final node = nodes[nodeId];
    if (node == null) {
      throw ArgumentError('Unknown node id: $nodeId');
    }
    if (TaxonomyService.hasDuplicateSiblingName(
      name: node.name,
      parentId: newParentId,
      nodes: nodes,
      excludeNodeId: nodeId,
      scope: node.scope,
    )) {
      throw ArgumentError('A sibling with the same name already exists.');
    }

    final finalNodes = TaxonomyService.reparentNode(
      nodes: nodes,
      nodeId: nodeId,
      newParentId: newParentId,
      requiredKind: requiredKind,
    );
    nodes.clear();
    nodes.addAll(finalNodes);
    return nodes[nodeId]!;
  }

  TaxonomyNode archiveNode(String nodeId) {
    final node = nodes[nodeId];
    if (node == null) {
      throw ArgumentError('Unknown node id: $nodeId');
    }

    final archived = node.copyWith(status: 'archived');
    nodes[nodeId] = archived;
    return archived;
  }

  List<TaxonomyNode> childrenOf(String? parentId) {
    final children =
        nodes.values.where((node) => node.parentId == parentId).toList();
    children
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return children;
  }

  List<TaxonomySearchResult> search(String query,
      {TaxonomyNodeKind? kind, String? courseId}) {
    final q = TaxonomyService.normalizeName(query).toLowerCase();
    final results = <TaxonomySearchResult>[];

    for (final node in nodes.values) {
      if (node.status == 'archived') {
        continue;
      }
      if (kind != null && node.kind != kind) {
        continue;
      }
      final associatedWithCourse = courseId != null &&
          (node.courseId == courseId ||
              node.courseAssociations.contains(courseId));
      if (courseId != null &&
          courseId.isNotEmpty &&
          node.scope == 'course' &&
          !associatedWithCourse) {
        continue;
      }

      final searchable = <String>{
        node.name,
        ...node.aliases,
        ...TaxonomyService.findAncestorIds(nodes: nodes, nodeId: node.id)
            .map((id) => nodes[id]?.name ?? ''),
      }
          .where((value) => value.isNotEmpty)
          .map((value) => value.toLowerCase())
          .toList();

      final matches = searchable.where((value) => value.contains(q)).toList();
      if (q.isEmpty || matches.isNotEmpty) {
        results.add(TaxonomySearchResult(
          nodeId: node.id,
          name: node.name,
          kind: node.kind.name,
          path: TaxonomyService.buildBreadcrumb(nodes: nodes, nodeId: node.id),
          score: matches.isEmpty ? 0 : matches.length,
        ));
      }
    }

    results.sort((a, b) {
      if (courseId != null && courseId.isNotEmpty) {
        final aNode = nodes[a.nodeId]!;
        final bNode = nodes[b.nodeId]!;
        final aCourseSpecific = aNode.courseId == courseId ||
            aNode.courseAssociations.contains(courseId);
        final bCourseSpecific = bNode.courseId == courseId ||
            bNode.courseAssociations.contains(courseId);
        if (aCourseSpecific != bCourseSpecific) {
          return aCourseSpecific ? -1 : 1;
        }
      }
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    return results;
  }
}

class TaxonomySearchResult {
  const TaxonomySearchResult({
    required this.nodeId,
    required this.name,
    required this.kind,
    required this.path,
    required this.score,
  });

  final String nodeId;
  final String name;
  final String kind;
  final String path;
  final int score;
}
