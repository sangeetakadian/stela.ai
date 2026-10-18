import 'package:flutter/material.dart';

import '../models/assessment_tagging.dart';
import '../services/taxonomy_service.dart';

class AssessmentTagEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? initialTag;
  final TaxonomyRegistry? taxonomyRegistry;
  final bool sourceIsStale;

  const AssessmentTagEditorDialog({
    super.key,
    this.initialTag,
    this.taxonomyRegistry,
    this.sourceIsStale = false,
  });

  @override
  State<AssessmentTagEditorDialog> createState() =>
      _AssessmentTagEditorDialogState();
}

class _AssessmentTagEditorDialogState extends State<AssessmentTagEditorDialog> {
  late final TaxonomyRegistry registry;
  late final List<TaxonomyNode> conceptNodes;
  late final List<TaxonomyNode> skillNodes;

  late final Set<String> selectedConceptIds;
  late final Set<String> selectedSkillIds;
  late String? primaryConceptId;

  String conceptQuery = '';
  String skillQuery = '';

  @override
  void initState() {
    super.initState();
    registry = widget.taxonomyRegistry ?? TaxonomyRegistry();
    conceptNodes = registry.activeNodesByKind(TaxonomyNodeKind.concept);
    skillNodes = registry.activeNodesByKind(TaxonomyNodeKind.skill);

    final tag = widget.initialTag ?? const <String, dynamic>{};
    final rawConcepts = tag['conceptIds'];
    final rawSkills = tag['assessedSkillIds'];

    selectedConceptIds = <String>{
      if (rawConcepts is List) ...rawConcepts.map((item) => item.toString()),
    };
    selectedSkillIds = <String>{
      if (rawSkills is List) ...rawSkills.map((item) => item.toString()),
    };
    primaryConceptId = (tag['primaryConceptId'] ?? '').toString();
    if (primaryConceptId != null &&
        primaryConceptId!.isNotEmpty &&
        !selectedConceptIds.contains(primaryConceptId)) {
      primaryConceptId =
          selectedConceptIds.isNotEmpty ? selectedConceptIds.first : null;
    }
    if ((primaryConceptId == null || primaryConceptId!.isEmpty) &&
        selectedConceptIds.isNotEmpty) {
      primaryConceptId = selectedConceptIds.first;
    }
  }

  List<TaxonomyNode> _filteredConcepts() {
    final query = conceptQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return conceptNodes;
    }

    return conceptNodes.where((node) {
      final searchable = <String>{
        node.name,
        TaxonomyService.buildBreadcrumb(nodes: registry.nodes, nodeId: node.id),
      }.join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  List<TaxonomyNode> _filteredSkills() {
    final query = skillQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return skillNodes;
    }

    return skillNodes.where((node) {
      final searchable = <String>{
        node.name,
        TaxonomyService.buildBreadcrumb(nodes: registry.nodes, nodeId: node.id),
      }.join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleConcepts = _filteredConcepts();
    final visibleSkills = _filteredSkills();

    return AlertDialog(
      title: const Text('Topics & Skills'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.sourceIsStale) ...[
                const Text(
                  'The question changed since these tags were last reviewed. Confirm the mapping again before saving.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
                const SizedBox(height: 12),
              ],
              const Text('Concepts'),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search questions concepts',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => conceptQuery = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visibleConcepts.map((concept) {
                  final selected = selectedConceptIds.contains(concept.id);
                  final label = TaxonomyService.buildBreadcrumb(
                              nodes: registry.nodes, nodeId: concept.id)
                          .isNotEmpty
                      ? TaxonomyService.buildBreadcrumb(
                          nodes: registry.nodes, nodeId: concept.id)
                      : concept.name;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        if (selected) {
                          selectedConceptIds.remove(concept.id);
                          if (primaryConceptId == concept.id) {
                            primaryConceptId = selectedConceptIds.isNotEmpty
                                ? selectedConceptIds.first
                                : null;
                          }
                        } else {
                          selectedConceptIds.add(concept.id);
                          if (primaryConceptId == null ||
                              primaryConceptId!.isEmpty) {
                            primaryConceptId = concept.id;
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Primary concept'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visibleConcepts.map((concept) {
                  final conceptId = concept.id;
                  final enabled = selectedConceptIds.contains(conceptId);
                  final label = TaxonomyService.buildBreadcrumb(
                              nodes: registry.nodes, nodeId: concept.id)
                          .isNotEmpty
                      ? TaxonomyService.buildBreadcrumb(
                          nodes: registry.nodes, nodeId: concept.id)
                      : concept.name;
                  return FilterChip(
                    label: Text(label),
                    selected: primaryConceptId == conceptId,
                    onSelected: enabled
                        ? (_) {
                            setState(() {
                              primaryConceptId = conceptId;
                            });
                          }
                        : null,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Confirmed assessed skills'),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search skills',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => skillQuery = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visibleSkills.map((skill) {
                  final skillId = skill.id;
                  final selected = selectedSkillIds.contains(skillId);
                  return FilterChip(
                    label: Text(skill.name),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        if (selected) {
                          selectedSkillIds.remove(skillId);
                        } else {
                          selectedSkillIds.add(skillId);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final selectedList = selectedConceptIds.toList()..sort();
            final skillList = selectedSkillIds.toList()..sort();
            Navigator.pop(context, <String, dynamic>{
              ...?widget.initialTag,
              'conceptIds': selectedList,
              'conceptLabels': {
                for (final id in selectedList)
                  id: TaxonomyService.buildBreadcrumb(
                      nodes: registry.nodes, nodeId: id),
              },
              'primaryConceptId': primaryConceptId,
              'assessedSkillIds': skillList,
              'skillLabels': {
                for (final id in skillList)
                  id: TaxonomyService.buildBreadcrumb(
                      nodes: registry.nodes, nodeId: id),
              },
              'suggestedSkillIds': const <String>[],
              'reviewed': true,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
