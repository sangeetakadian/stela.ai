# Assessment tagging: completed foundation and next step

## What was completed

This milestone implemented the first safe, backward-compatible foundation for the hierarchical assessment-tagging feature in the Flutter app.

The completed work includes:

- a dedicated question/tagging domain model in `frontend/lib/models/assessment_tagging.dart`
- a compatibility-safe round-trip update in `frontend/lib/models/quiz_model.dart`
- a focused regression test suite covering preserved metadata and evidence aggregation

### What the model does

The new model layer is intentionally separate from the legacy quiz payload so the existing quiz/question arrays can continue to behave as before while tagging metadata is stored in an additive sidecar structure.

It introduces:

- `TaxonomyNode` for concept and skill hierarchy records
- `QuestionTagMetadata` for reviewed or proposed mapping data tied to a quiz and question
- `QuestionEvidenceEntry` and `AssessmentEvidenceAggregator` for evidence-based roll-up logic

This gives the project a structured representation for:

- concept/skill taxonomy records
- multi-concept question tagging
- primary concept attribution
- skill suggestions vs confirmed skills
- evidence aggregation without breaking legacy quiz data

## Why this task was needed

The specification for hierarchical assessment tagging explicitly requires a backward-compatible database contract. Existing records already store quiz content in mirrored arrays (`questions` / `facultyQuestions`) and the current app can reconstruct or rewrite those maps. That means embedding new tag data directly into legacy question maps is unsafe and can cause data loss or compatibility regressions.

The completed model work resolves the first blocker by separating:

- the legacy quiz structure that existing clients expect
- the additive metadata model used for future assessment-tagging work

This is the foundation required before any faculty UI, taxonomy management, or student-feedback logic can be implemented safely.

## How it will be used next

The next implementation step is the taxonomy service layer. That service will actually enforce the rules described in the assessment-tagging spec, including:

- validating node names and scopes
- preventing invalid parentage and cycles
- building breadcrumb/path metadata
- preventing duplicate sibling names within a parent scope
- maintaining stable ID-based references across question metadata

Once that service exists, the next layer can safely connect the faculty tagging UI to real taxonomy records and metadata sidecars without risking data corruption.

## Expected next step

The immediate follow-up is to implement a pure taxonomy service and tests that cover:

- valid/invalid create and reparent operations
- cycle prevention
- breadcrumb construction
- sibling duplicate detection
- parent-kind validation
- consistent ID-based lookups

This keeps the project aligned with the spec’s staged implementation order: model foundation first, then taxonomy service, then faculty tagging UI, then evidence feedback.

## Current status and remaining work

The status table below is the release source of truth; implementation or unit tests do not imply emulator, staging, or research validation.

### Staging release checklist

| Requirement | Status | Evidence and remaining gate |
|---|---|---|
| Faculty question tagging with confirmed concepts/skills | Implemented | Editor and taxonomy management are wired into quiz management. Full authorized faculty workflow is not yet integration-tested. |
| Additive sidecar persistence and legacy quiz payload preservation | Unit-tested | `assessment_tagging_service_test.dart` and `assessment_tagging_test.dart`; real old-client coexistence is not verified. |
| Reopen and stale-fingerprint handling | Unit-tested | Tagging-service tests cover stable/changed fingerprints and metadata preservation; UI save/reopen is not Emulator-verified. |
| Student scoring identity, evidence attribution, threshold and abstention | Unit-tested | `assessment_feedback_service_test.dart` covers reviewed/primary tags, invalid/stale mappings, duplicate identity, skill threshold, missing score data, and parent-roll-up deduplication. Randomized end-to-end score alignment remains unverified. |
| RTDB rules use trusted role claims and restrict assigned faculty to one subject key | Implemented | `database.rules.json` checks `assessmentFaculty`, `assessmentSubjectKey`, `assessmentAdmin`, and `taxonomySteward`; rules are not yet Emulator-verified. |
| Trusted Admin SDK role/course claim provisioning | Blocked | No trusted provisioner or approved Firestore-to-claim synchronization exists in this repository. Until configured, protected writes fail closed. |
| Rules denial/allow matrix in Firebase Emulator | Blocked | Harness is in `frontend/rules_tests/`; run `npm run test:emulator` there after dependencies and Java are available. |
| Existing quiz, both Excel imports, images, editing, randomization and old-client compatibility | Blocked | Unit coverage does not yet prove both import workflows, historical payload behavior, image flows, answer alignment, or repeated-import behavior end to end. |
| Staging build, deployment, smoke test and rollback record | Blocked | No dedicated staging Firebase project/accounts or deployment approval has been provided. No environment has been deployed. |
| Expert review, pilot approval, ethics and diagnostic evaluation | Blocked | These are external research decisions; software tests are not evidence of scientific validity. |

### Completed in this phase

- Safe additive metadata models and legacy quiz round-trip protection
- Taxonomy validation, Firebase serialization, faculty tagging UI, and taxonomy management UI
- Sidecar load/save with stable question fingerprints, explicit stale reconfirmation, and preservation of unknown metadata
- Quiz-scoped student evidence based on per-question earned/possible marks, reviewed mappings, and explicit insufficient-evidence states
- Concept ancestor roll-up with per-question deduplication and abstention when taxonomy is unavailable
- Draft RTDB authorization now checks server-issued Firebase Auth custom claims rather than a client-writable role mirror
- Firebase Emulator test harness and CI workflow added; execution remains a release gate

### Remaining work, in release order

1. Establish a trusted Admin SDK custom-claims provisioner from the institution-approved role and course-assignment source. The pilot contract currently uses a single `assessmentSubjectKey`; multi-course claim semantics are not implemented.
2. Run and fix the RTDB allow/deny matrix in the Firebase Emulator, including legitimate faculty, cross-course faculty, students, admins/stewards, missing claims, and private student evidence.
3. Add end-to-end tests for faculty tag/save/reopen/edit/stale recovery, student randomization/scoring/evidence, both Excel creation flows, images, and old quiz records.
4. Run the established Flutter build/test gates and a compatibility review against supported legacy payloads.
5. Only after the above gates, use an approved staging Firebase project and staging accounts for deployment and smoke tests; record commit and rollback steps. Do not deploy these draft rules to production.
6. Keep expert review, pilot approval, ethics, and empirical diagnostic validation as separate external gates.

### Current continuation

The taxonomy editor now reads the Firebase registry instead of silently using a fixed pilot list. An absent registry is returned as empty and is not automatically seeded or written; taxonomy persistence occurs only after a faculty member explicitly creates or archives a node. Sibling uniqueness now normalizes case/whitespace within scope, reparent checks destination collisions, and course-specific search results are prioritized while shared records remain visible.

The chosen authorization direction is Firebase Auth custom claims issued only by a trusted Admin SDK process. The draft rules require `assessmentFaculty: true` with an exact `assessmentSubjectKey` for faculty writes, or `assessmentAdmin: true` / `taxonomySteward: true` for stewarded cross-course writes. Students may read reviewed metadata and write only their own evidence. Claims are not provisioned by the app. The existing UI still resolves roles from Firestore, so the approved role/course source and trusted synchronizer must be established before faculty can write. Missing claims deny protected writes.

### Next implementation target

The emulator allow/deny matrix still needs a Java 17+ runtime available to Firebase CLI. Then the project needs a trusted claim provisioner connected to the institution-approved role/course source. Historical review and broad old-client compatibility remain separate checks; no staging deployment is safe until authorization and compatibility gates pass.

### Latest implementation progress

The current increment adds stable question fingerprinting and review-safe identity tracking to the sidecar metadata. This is the last compatibility blocker before the app can safely support historical and repeated question review without silently misapplying tags to a different question variant.

This work matters because the tag sidecar must remain anchored to the actual scored question, even after re-open/re-save cycles or quiz edits. Without that identity boundary, faculty review can accidentally attach tags to the wrong question object or stale legacy clone when a quiz is edited.

The next short-term milestone is the Firebase-backed taxonomy registry and permission model so the app can stop relying on seeded local data and begin enforcing course-scoped, reviewed taxonomy writes.

This iteration adds the Firebase serialization contract for taxonomy nodes so the registry can be stored and reconstructed from the same shape expected by the assessment-tagging data model. The implementation preserves the compatibility-first design while making the taxonomy layer ready to connect to a real course-scoped data source.

I also added the initial RTDB security contract in [frontend/database.rules.json](../frontend/database.rules.json). This locks the taxonomy and question-tagging paths behind authenticated faculty/admin roles and keeps student evidence scoped to the student's own data. The remaining step is to connect these rules to the actual deployed user-role source and course membership model so they are enforced against the real institution schema.

The current continuation moves the app one step closer to operational use by adding a taxonomy management dialog that lets faculty create and archive taxonomy nodes directly from the quiz editor, while persisting the in-memory registry to the Firebase taxonomy path for the active subject. This is the practical bridge between the safe model layer and the real governance workflow the spec requires.

The latest increment adds per-question earned/possible marks to quiz submissions and a student-facing evidence summary. Only reviewed tags with matching fingerprints and valid score denominators contribute; direct primary-concept evidence is shown for this quiz, while skills remain “Insufficient evidence” until five distinct questions are available. Questions fetch their sidecar tags before randomized order/options are applied, preserving score/tag alignment. A v2 canonical fingerprint now covers the complete question map except top-level identity/tag-cache fields, so content changes (including marks and nested coding criteria) make older mappings stale. Students may read absent tag leaves and reviewed metadata, but cannot read existing unreviewed metadata under the proposed RTDB rules.

Faculty edit/reopen now loads the same sidecar data. Stale mappings are shown for explicit faculty reconfirmation and are not persisted unless the reviewer saves from the tag editor. This prevents a normal quiz edit from silently refreshing a stale fingerprint and blessing an old mapping. Existing unknown sidecar fields are retained when faculty re-save a mapping, and archived taxonomy nodes remain unavailable for new selection.

The latest evidence increment rolls a reviewed concept association up through its taxonomy ancestors, while de-duplicating each scored question at each concept. Taxonomy is loaded alongside question tags before shuffling and passed to the result feedback service; without the registry, only directly tagged concept evidence is shown and no parent evidence is inferred. This enables users to see a cautious summary at broader concept levels without multiplying marks when a question has sibling concept tags.

Validation this increment: `flutter test test/assessment_feedback_service_test.dart test/assessment_tagging_service_test.dart test/assessment_tagging_test.dart test/taxonomy_service_test.dart test/widget_test.dart` passes (28 tests). New regression coverage verifies that two sibling tags contribute a question only once to their shared ancestor and that missing taxonomy data does not invent parent evidence. The rules test JavaScript passes `node --check`, and `npm ls --depth=0` confirms the pinned direct dependencies are installed. `npm run test:emulator` is blocked before tests start because Firebase CLI cannot spawn `java -version`; no rules pass is claimed. The Dart analyzer previously reported no errors in changed Dart files, only informational lints, but the Dart tooling service could not initialize in the current sandbox during this continuation.

### Staging and rollback runbook

No staging project or staging credentials are configured or used by this change. After a trusted claim provisioner and the emulator/compatibility gates are in place:

1. Use a dedicated staging Firebase project and staging accounts; inspect the selected project with `firebase projects:list` and verify the expected project ID before deployment.
2. From `frontend/`, build the web client with `flutter build web --release`.
3. Deploy only to the approved staging project with `firebase deploy --only database,hosting --project <staging-project-id>`. Do not deploy production rules from this branch without a separate explicit authorization.
4. Run faculty sign-in, tag/save/reopen/edit, student attempt/evidence, and denied-user smoke checks; record the deployed Git commit and Firebase project ID.
5. Roll back by re-deploying the previously approved staging rules and hosting version (or restoring the previous hosting release and database rules through Firebase Console release history). Keep the previous rules artifact with the release record; do not use an unreviewed local copy as rollback material.

No staging deployment or scientific validation is claimed. Staging remains blocked on the trusted role/course claim provisioner, Firebase Emulator execution, compatibility integration coverage, and approved staging project/accounts. The pilot is not ready for deployment.
