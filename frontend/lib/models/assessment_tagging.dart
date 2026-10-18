// Data model and pure helpers for the hierarchical assessment-tagging pilot.
//
// Keep this separate from legacy quiz payloads so question arrays remain
// compatible while new metadata is stored in an additive sidecar location.

class TaxonomyNode {
  final String id;
  final TaxonomyNodeKind kind;
  final String name;
  final String? parentId;
  final String scope;
  final String? courseId;
  final String? definition;
  final List<String> aliases;
  final String? status;
  final List<String> courseAssociations;
  final Map<String, dynamic> extraFields;

  const TaxonomyNode({
    required this.id,
    required this.kind,
    required this.name,
    this.parentId,
    this.scope = 'shared',
    this.courseId,
    this.definition,
    this.aliases = const [],
    this.status,
    this.courseAssociations = const [],
    this.extraFields = const {},
  });

  String get breadcrumb {
    final paths = <String>[];
    if (parentId != null && parentId!.isNotEmpty) {
      paths.add(parentId!);
    }
    paths.add(name);
    return paths.join(' / ');
  }

  bool get isConcept => kind == TaxonomyNodeKind.concept;
  bool get isSkill => kind == TaxonomyNodeKind.skill;

  TaxonomyNode copyWith({
    String? id,
    TaxonomyNodeKind? kind,
    String? name,
    String? parentId,
    bool clearParentId = false,
    String? scope,
    String? courseId,
    String? definition,
    List<String>? aliases,
    String? status,
    List<String>? courseAssociations,
    Map<String, dynamic>? extraFields,
  }) {
    return TaxonomyNode(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      parentId: clearParentId ? null : parentId ?? this.parentId,
      scope: scope ?? this.scope,
      courseId: courseId ?? this.courseId,
      definition: definition ?? this.definition,
      aliases: aliases ?? this.aliases,
      status: status ?? this.status,
      courseAssociations: courseAssociations ?? this.courseAssociations,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'name': name,
      if (parentId != null && parentId!.isNotEmpty) 'parentId': parentId,
      'scope': scope,
      if (courseId != null && courseId!.isNotEmpty) 'courseId': courseId,
      if (definition != null && definition!.isNotEmpty)
        'definition': definition,
      if (aliases.isNotEmpty) 'aliases': aliases,
      if (status != null && status!.isNotEmpty) 'status': status,
      if (courseAssociations.isNotEmpty)
        'courseAssociations': courseAssociations,
      ...extraFields,
    };
  }

  factory TaxonomyNode.fromMap(Map<String, dynamic> map) {
    final kindValue = (map['kind'] ?? map['type'] ?? 'concept').toString();
    final kind = kindValue == 'skill'
        ? TaxonomyNodeKind.skill
        : TaxonomyNodeKind.concept;

    return TaxonomyNode(
      id: map['id']?.toString() ?? '',
      kind: kind,
      name: map['name']?.toString() ?? '',
      parentId: map['parentId']?.toString(),
      scope: map['scope']?.toString() ?? 'shared',
      courseId: map['courseId']?.toString(),
      definition: map['definition']?.toString(),
      aliases: (map['aliases'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      status: map['status']?.toString(),
      courseAssociations:
          (map['courseAssociations'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      extraFields: Map<String, dynamic>.from(
        map.map((key, value) => MapEntry(key.toString(), value))
          ..removeWhere((key, _) => [
                'id',
                'kind',
                'type',
                'name',
                'parentId',
                'scope',
                'courseId',
                'definition',
                'aliases',
                'status',
                'courseAssociations'
              ].contains(key)),
      ),
    );
  }
}

enum TaxonomyNodeKind {
  concept,
  skill,
}

class QuestionTagMetadata {
  final String quizId;
  final String questionId;
  final String? stableQuestionId;
  final List<String> conceptIds;
  final String? primaryConceptId;
  final List<String> assessedSkillIds;
  final List<String> suggestedSkillIds;
  final List<String> proposedSkillIds;
  final bool reviewed;
  final String? sourceFingerprint;
  final String metadataVersion;
  final DateTime updatedAt;
  final Map<String, dynamic> extraFields;

  QuestionTagMetadata({
    required this.quizId,
    required this.questionId,
    this.stableQuestionId,
    this.conceptIds = const [],
    this.primaryConceptId,
    this.assessedSkillIds = const [],
    this.suggestedSkillIds = const [],
    this.proposedSkillIds = const [],
    this.reviewed = false,
    this.sourceFingerprint,
    this.metadataVersion = '1',
    DateTime? updatedAt,
    this.extraFields = const {},
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get sidecarPath => 'question_tagging/$quizId/$questionId';

  QuestionTagMetadata copyWith({
    String? quizId,
    String? questionId,
    String? stableQuestionId,
    List<String>? conceptIds,
    String? primaryConceptId,
    List<String>? assessedSkillIds,
    List<String>? suggestedSkillIds,
    List<String>? proposedSkillIds,
    bool? reviewed,
    String? sourceFingerprint,
    String? metadataVersion,
    DateTime? updatedAt,
    Map<String, dynamic>? extraFields,
  }) {
    return QuestionTagMetadata(
      quizId: quizId ?? this.quizId,
      questionId: questionId ?? this.questionId,
      stableQuestionId: stableQuestionId ?? this.stableQuestionId,
      conceptIds: conceptIds ?? this.conceptIds,
      primaryConceptId: primaryConceptId ?? this.primaryConceptId,
      assessedSkillIds: assessedSkillIds ?? this.assessedSkillIds,
      suggestedSkillIds: suggestedSkillIds ?? this.suggestedSkillIds,
      proposedSkillIds: proposedSkillIds ?? this.proposedSkillIds,
      reviewed: reviewed ?? this.reviewed,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      metadataVersion: metadataVersion ?? this.metadataVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'quizId': quizId,
      'questionId': questionId,
      if (stableQuestionId != null && stableQuestionId!.isNotEmpty)
        'stableQuestionId': stableQuestionId,
      'conceptIds': conceptIds,
      if (primaryConceptId != null && primaryConceptId!.isNotEmpty)
        'primaryConceptId': primaryConceptId,
      'assessedSkillIds': assessedSkillIds,
      'suggestedSkillIds': suggestedSkillIds,
      'proposedSkillIds': proposedSkillIds,
      'reviewed': reviewed,
      'sourceFingerprint': sourceFingerprint,
      'metadataVersion': metadataVersion,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      ...extraFields,
    };
    return map;
  }

  factory QuestionTagMetadata.fromMap(Map<String, dynamic> map) {
    final rawExtra = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      if (![
        'quizId',
        'questionId',
        'stableQuestionId',
        'conceptIds',
        'primaryConceptId',
        'assessedSkillIds',
        'suggestedSkillIds',
        'proposedSkillIds',
        'reviewed',
        'sourceFingerprint',
        'metadataVersion',
        'updatedAt',
      ].contains(key)) {
        rawExtra[key] = entry.value;
      }
    }

    return QuestionTagMetadata(
      quizId: map['quizId']?.toString() ?? '',
      questionId: map['questionId']?.toString() ?? '',
      stableQuestionId: map['stableQuestionId']?.toString(),
      conceptIds: _asStringList(map['conceptIds']),
      primaryConceptId: map['primaryConceptId']?.toString(),
      assessedSkillIds: _asStringList(map['assessedSkillIds']),
      suggestedSkillIds: _asStringList(map['suggestedSkillIds']),
      proposedSkillIds: _asStringList(map['proposedSkillIds']),
      reviewed: map['reviewed'] == true,
      sourceFingerprint: map['sourceFingerprint']?.toString(),
      metadataVersion: map['metadataVersion']?.toString() ?? '1',
      updatedAt: _parseDateTime(map['updatedAt']),
      extraFields: rawExtra,
    );
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    if (value == null) {
      return const [];
    }
    return [value.toString()];
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) {
      return DateTime.now();
    }
    if (value is DateTime) {
      return value;
    }
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }
}

class QuestionEvidenceEntry {
  final String questionId;
  final String? conceptId;
  final String? skillId;
  final double earnedMarks;
  final double possibleMarks;
  final bool eligible;

  const QuestionEvidenceEntry({
    required this.questionId,
    this.conceptId,
    this.skillId,
    required this.earnedMarks,
    required this.possibleMarks,
    this.eligible = true,
  });

  double get ratio => possibleMarks <= 0 ? 0.0 : earnedMarks / possibleMarks;
  bool get hasDenominator => possibleMarks > 0;
}

class EvidenceSummary {
  final double earnedMarks;
  final double possibleMarks;
  final int distinctQuestionCount;
  final String status;

  const EvidenceSummary({
    required this.earnedMarks,
    required this.possibleMarks,
    required this.distinctQuestionCount,
    required this.status,
  });

  double get ratio => possibleMarks <= 0 ? 0.0 : earnedMarks / possibleMarks;
  bool get hasSufficientEvidence =>
      distinctQuestionCount > 0 && possibleMarks > 0;
}

class AssessmentEvidenceAggregator {
  static EvidenceSummary summarize(
    List<QuestionEvidenceEntry> entries, {
    int minimumEvidenceItems = 5,
  }) {
    if (entries.isEmpty) {
      return const EvidenceSummary(
        earnedMarks: 0,
        possibleMarks: 0,
        distinctQuestionCount: 0,
        status: 'Not assessed',
      );
    }

    final deduped = <String, QuestionEvidenceEntry>{};
    for (final entry in entries) {
      if (!entry.eligible) {
        continue;
      }
      final key =
          '${entry.questionId}|${entry.conceptId ?? ''}|${entry.skillId ?? ''}';
      final existing = deduped[key];
      if (existing == null) {
        deduped[key] = entry;
      } else {
        deduped[key] = QuestionEvidenceEntry(
          questionId: entry.questionId,
          conceptId: entry.conceptId,
          skillId: entry.skillId,
          earnedMarks: existing.earnedMarks + entry.earnedMarks,
          possibleMarks: existing.possibleMarks + entry.possibleMarks,
          eligible: true,
        );
      }
    }

    final uniqueQuestions =
        deduped.values.map((entry) => entry.questionId).toSet().length;

    double earned = 0;
    double possible = 0;
    for (final entry in deduped.values) {
      earned += entry.earnedMarks;
      possible += entry.possibleMarks;
    }

    String status = 'Insufficient evidence';
    if (possible <= 0) {
      status = 'Not assessed';
    } else if (uniqueQuestions >= minimumEvidenceItems) {
      status = 'Mixed evidence';
    } else if (uniqueQuestions > 0) {
      status = 'Based on this quiz';
    }

    return EvidenceSummary(
      earnedMarks: earned,
      possibleMarks: possible,
      distinctQuestionCount: uniqueQuestions,
      status: status,
    );
  }
}
