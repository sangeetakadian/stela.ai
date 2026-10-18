import 'package:flutter/material.dart';

import '../models/assessment_tagging.dart';
import '../services/taxonomy_service.dart';

class TaxonomyManagementDialog extends StatefulWidget {
  final String subjectKey;
  final TaxonomyRegistry initialRegistry;

  const TaxonomyManagementDialog({
    super.key,
    required this.subjectKey,
    required this.initialRegistry,
  });

  @override
  State<TaxonomyManagementDialog> createState() => _TaxonomyManagementDialogState();
}

class _TaxonomyManagementDialogState extends State<TaxonomyManagementDialog> {
  late TaxonomyRegistry registry;
  final TextEditingController nameController = TextEditingController();
  String selectedKind = 'concept';
  String? selectedParentId;
  String query = '';

  @override
  void initState() {
    super.initState();
    registry = TaxonomyRegistry(initialNodes: Map<String, TaxonomyNode>.from(widget.initialRegistry.nodes));
  }

  List<TaxonomyNode> get visibleNodes {
    final kind = selectedKind == 'concept' ? TaxonomyNodeKind.concept : TaxonomyNodeKind.skill;
    final items = registry.search(query, kind: kind);
    return items
        .map((result) => registry.nodes[result.nodeId]!)
        .where((node) => node.status != 'archived')
        .toList();
  }

  Future<void> _persist() async {
    try {
      await registry.persistToFirebase(subjectKey: widget.subjectKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taxonomy saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save taxonomy: $e')),
        );
      }
    }
  }

  Future<void> _createNode() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a taxonomy name first.')),
      );
      return;
    }

    final kind = selectedKind == 'concept' ? TaxonomyNodeKind.concept : TaxonomyNodeKind.skill;
    final nodeId = '${kind.name}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      registry.createNode(
        id: nodeId,
        kind: kind,
        name: name,
        parentId: selectedParentId,
        scope: 'shared',
      );
      nameController.clear();
      selectedParentId = null;
      await _persist();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create node: $e')),
        );
      }
    }
  }

  Future<void> _archiveNode(String nodeId) async {
    try {
      registry.archiveNode(nodeId);
      await _persist();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to archive node: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentOptions = registry.nodes.values
        .where((node) => node.kind.name == selectedKind && node.status != 'archived')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return AlertDialog(
      title: const Text('Manage taxonomy'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Kind: '),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'concept', label: Text('Concept')),
                    ButtonSegment(value: 'skill', label: Text('Skill')),
                  ],
                  selected: {selectedKind},
                  onSelectionChanged: (value) {
                    setState(() {
                      selectedKind = value.first;
                      selectedParentId = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedParentId,
              decoration: const InputDecoration(
                labelText: 'Parent (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('No parent')),
                ...parentOptions.map((node) => DropdownMenuItem<String>(
                      value: node.id,
                      child: Text(TaxonomyService.buildBreadcrumb(nodes: registry.nodes, nodeId: node.id)),
                    )),
              ],
              onChanged: (value) => setState(() => selectedParentId = value),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _createNode,
                icon: const Icon(Icons.add),
                label: const Text('Create node'),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Existing taxonomy'),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by name or path',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: ListView.separated(
                itemCount: visibleNodes.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final node = visibleNodes[index];
                  final parentPath = TaxonomyService.buildBreadcrumb(nodes: registry.nodes, nodeId: node.id);
                  return ListTile(
                    title: Text(node.name),
                    subtitle: Text('$parentPath • ${node.kind.name}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.archive_outlined),
                      tooltip: 'Archive',
                      onPressed: () => _archiveNode(node.id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
