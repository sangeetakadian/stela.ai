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

## How it was used after the model foundation

At this milestone, the next implementation step was the taxonomy service layer. It enforces the rules described in the assessment-tagging spec, including:

- validating node names and scopes
- preventing invalid parentage and cycles
- building breadcrumb/path metadata
- preventing duplicate sibling names within a parent scope
- maintaining stable ID-based references across question metadata

That service and the connected UI are now implemented; the current release gates are listed below.

## Expected next step at the time

The immediate follow-up at the time was to implement a pure taxonomy service and tests that cover:

- valid/invalid create and reparent operations
- cycle prevention
- breadcrumb construction
- sibling duplicate detection
- parent-kind validation
- consistent ID-based lookups

This kept the project aligned with the spec’s staged implementation order: model foundation first, then taxonomy service, then faculty tagging UI, then evidence feedback.

## Current status and remaining work

The status table below is the release source of truth; implementation or unit tests do not imply Emulator, pilot-deployment, or research validation.

### Internal pilot release checklist

| Requirement | Status | Evidence and remaining gate |
|---|---|---|
| Faculty question tagging with confirmed concepts/skills | Unit-tested | Faculty can open the tag editor from each question; `assessment_tagging_ui_test.dart` verifies concept/skill selection and saving. Live authorized Firebase save/reopen remains unverified. |
| Student question-level and competency-summary evidence UI | Unit-tested | `assessment_tagging_ui_test.dart` verifies current reviewed concept/skill labels and question score are visible, and suggestions are not presented as confirmed evidence. Live quiz-attempt flow remains unverified. |
| Additive sidecar persistence and legacy quiz payload preservation | Unit-tested | `assessment_tagging_service_test.dart` and `assessment_tagging_test.dart`; real old-client coexistence is not verified. |
| Reopen and stale-fingerprint handling | Unit-tested | Tagging-service tests cover stable/changed fingerprints and metadata preservation; UI save/reopen is not Emulator-verified. |
| Student scoring identity, evidence attribution, threshold and abstention | Unit-tested | `assessment_feedback_service_test.dart` covers reviewed/primary tags, invalid/stale mappings, duplicate identity, skill threshold, missing score data, and parent-roll-up deduplication. Randomized end-to-end score alignment remains unverified. |
| Candidate RTDB rules for quizzes, taxonomy, and question tags | Emulator-verified | The isolated Emulator rule suite covers authenticated legacy quiz reads, faculty writes limited to the claimed subject, course denial, reviewed-tag student reads, and missing claims. These are candidate rules only, not the rules currently deployed to the shared Firebase project. |
| Trusted Admin SDK role/course claim provisioning | Unit-tested | A guarded CLI tool supports explicit pilot-account claims via ADC in `frontend/rules_tests/provision_assessment_claims.mjs`; it does not infer roles from client-created Firestore documents. The institution must still approve the role/course roster and an authorized operator must apply claims. |
| Candidate Firestore rule for a student's own quiz submission | Emulator-verified | The isolated rules suite permits self-owned submission creates and denies anonymous, other-user, and conflicting-UID writes. The candidate rule has not been merged into or deployed to the shared project's active rules. |
| Current shared-project rules and feature-path authorization | Blocked | Firebase CLI reports no authorized accounts; an unauthenticated read of the RTDB rules endpoint returns HTTP 403. The active RTDB and Firestore rules therefore could not be inspected. No production rules or data were changed. |
| Compatibility with other applications using the shared Firebase project | Blocked | The code keeps tagging metadata in sidecar paths and preserves legacy quiz fields, but older-app access under the active shared rules is unverified. Do not deploy the Emulator candidate rules as production rules: they are not a merge with the active rules and could deny unrelated paths. |
| Existing quiz, both Excel imports, images, editing, randomization and old-client compatibility | Blocked | Unit coverage does not yet prove both import workflows, historical payload behavior, image flows, answer alignment, or repeated-import behavior end to end. |
| Separate professor-facing Vercel deployment using current Firebase config | Deployed; workflow blocked | The separate Preview deployment is live at [stela-professor-pilot-5m1hxgn6p-stelaai.vercel.app](https://stela-professor-pilot-5m1hxgn6p-stelaai.vercel.app/) from commit `1f036dd97b372741d58aa25ec6a979894390331e`. The app shell and Flutter canvas load, but a `manifest.json` request was redirected to Vercel SSO, so professor accessibility and authenticated faculty/student workflows are not confirmed. Active shared Firebase rules and authorized test accounts are still unavailable. |
| Expert review, pilot approval, ethics and diagnostic evaluation | Blocked | These are external research decisions; software tests are not evidence of scientific validity. |

### Completed in this phase

- Safe additive metadata models and legacy quiz round-trip protection
- Taxonomy validation, Firebase serialization, faculty tagging UI, and taxonomy management UI
- Sidecar load/save with stable question fingerprints, explicit stale reconfirmation, and preservation of unknown metadata
- Quiz-scoped student evidence based on per-question earned/possible marks, reviewed mappings, and explicit insufficient-evidence states
- Concept ancestor roll-up with per-question deduplication and abstention when taxonomy is unavailable
- Candidate Emulator rules add quiz reads for authenticated users, claim-scoped faculty quiz writes, and student-owned attempt creation; these candidates are isolated from the normal Firebase deploy config
- Normal Vercel builds continue using the checked-in shared-project Firebase options; the Preview validation build uses the existing code-execution backend
- The dedicated professor-facing Vercel project has a successful Preview deployment; the existing production project and shared Firebase rules/data were not changed
- App package version and splash label are both `8.0` (`8.0.0+8` package metadata)

### Remaining work, in release order

1. Obtain authorized read access to the active RTDB and Firestore rules for `stela23-f9a52`, or have a Firebase administrator provide the current rules exports. Merge only the minimal necessary additive rules, if the active policy lacks the required operations, then validate the merged rules in the Emulator.
2. Run the live workflow using an authorized professor account and a dedicated test quiz that does not alter existing quiz records; verify tag save/reopen/stale review and student attempt/evidence.
3. Add end-to-end coverage for both Excel import paths, images, historical quiz data, randomized scoring alignment, and old-client coexistence.
4. Confirm the Preview's access policy, then run the faculty and student workflows with authorized accounts and a dedicated test quiz. Do not change the existing `stela_ai` deployment.
5. Keep expert review, pilot approval, ethics, and empirical diagnostic validation as separate external gates.

### Current continuation

The taxonomy editor now reads the Firebase registry instead of silently using a fixed pilot list. An absent registry is returned as empty and is not automatically seeded or written; taxonomy persistence occurs only after a faculty member explicitly creates or archives a node. Sibling uniqueness now normalizes case/whitespace within scope, reparent checks destination collisions, and course-specific search results are prioritized while shared records remain visible.

The chosen authorization direction is Firebase Auth custom claims issued only by a trusted Admin SDK process. The draft rules require `assessmentFaculty: true` with an exact `assessmentSubjectKey` for faculty writes, or `assessmentAdmin: true` / `taxonomySteward: true` for stewarded cross-course writes. Students may read reviewed metadata and write only their own evidence. Claims are not provisioned by the app. A guarded operator CLI at `frontend/rules_tests/provision_assessment_claims.mjs` defaults to dry-run, requires exact project confirmation before applying, preserves unrelated claims, and can grant/revoke only the managed assessment claims. The existing UI resolves roles from Firestore, but both faculty signup flows write `userRole: 'Faculty'` from the client, so that field is not an authoritative approval source for privileged claims. Existing subject records are also created by their owning signed-in user. The CLI must only be used after the institution approves the account-to-course roster; missing claims deny protected writes.

### Current external gates

The Emulator allow/deny matrix has passed locally and in CI using Java 21, but it validates only the isolated candidate rules. The institution must provide access to the active shared-project rules and approve the faculty/admin/student roster and course key before any live writes or claims are attempted. Historical review and broad old-client compatibility remain separate checks.

### Latest implementation progress

The current increment adds stable question fingerprinting and review-safe identity tracking to the sidecar metadata. This is the last compatibility blocker before the app can safely support historical and repeated question review without silently misapplying tags to a different question variant.

This work matters because the tag sidecar must remain anchored to the actual scored question, even after re-open/re-save cycles or quiz edits. Without that identity boundary, faculty review can accidentally attach tags to the wrong question object or stale legacy clone when a quiz is edited.

The next short-term milestone is the Firebase-backed taxonomy registry and permission model so the app can stop relying on seeded local data and begin enforcing course-scoped, reviewed taxonomy writes.

This iteration adds the Firebase serialization contract for taxonomy nodes so the registry can be stored and reconstructed from the same shape expected by the assessment-tagging data model. The implementation preserves the compatibility-first design while making the taxonomy layer ready to connect to a real course-scoped data source.

I also added an Emulator-only RTDB candidate in [assessment_tagging.database.rules.test.json](../frontend/rules_tests/assessment_tagging.database.rules.test.json). It exercises claim-scoped faculty edits and student reads, but is deliberately excluded from the normal Firebase deploy configuration because it is not a merged copy of the shared project's active rules.

The current continuation moves the app one step closer to operational use by adding a taxonomy management dialog that lets faculty create and archive taxonomy nodes directly from the quiz editor, while persisting the in-memory registry to the Firebase taxonomy path for the active subject. This is the practical bridge between the safe model layer and the real governance workflow the spec requires.

The latest increment adds per-question earned/possible marks to quiz submissions and a student-facing evidence summary. Only reviewed tags with matching fingerprints and valid score denominators contribute; direct primary-concept evidence is shown for this quiz, while skills remain “Insufficient evidence” until five distinct questions are available. Questions fetch their sidecar tags before randomized order/options are applied, preserving score/tag alignment. A v2 canonical fingerprint now covers the complete question map except top-level identity/tag-cache fields, so content changes (including marks and nested coding criteria) make older mappings stale. Students may read absent tag leaves and reviewed metadata, but cannot read existing unreviewed metadata under the proposed RTDB rules.

Faculty edit/reopen now loads the same sidecar data. Stale mappings are shown for explicit faculty reconfirmation and are not persisted unless the reviewer saves from the tag editor. This prevents a normal quiz edit from silently refreshing a stale fingerprint and blessing an old mapping. Existing unknown sidecar fields are retained when faculty re-save a mapping, and archived taxonomy nodes remain unavailable for new selection.

The latest evidence increment rolls a reviewed concept association up through its taxonomy ancestors, while de-duplicating each scored question at each concept. Taxonomy is loaded alongside question tags before shuffling and passed to the result feedback service; without the registry, only directly tagged concept evidence is shown and no parent evidence is inferred. This enables users to see a cautious summary at broader concept levels without multiplying marks when a question has sibling concept tags.

Student results now distinguish a failed Firebase tag read from a quiz with no reviewed mappings: the summary and question evidence say when tag metadata could not be loaded, and tell faculty to confirm the tagged quiz was saved when the read succeeded but no eligible mappings were found. The result UI regression test verifies concept scores, concept parent roll-up, skill evidence thresholds, and the load-failure message. This does not verify or change the active shared-project rules.

Current validation: the full Flutter suite passes (32 tests); the web release build succeeds and embeds version `8.0.0` / build number `8`; the claims and Vercel routing suites pass (11 tests); and the RTDB/Firestore Emulator suite passes (22 tests) using Java 21. Commit `1f036dd97b372741d58aa25ec6a979894390331e` also aligns the splash label with version `8.0`; its focused widget test passes. GitHub Actions run `39124080527` passed validation and deployed the Preview listed above. The build reports the existing WebAssembly dry-run incompatibility from `universal_html`/`dart:html`; normal web compilation succeeds. Emulator results validate only the checked-in test candidates, not the deployed shared Firebase rules. The deployed rules could not be read because Firebase CLI has no authorized account and the unauthenticated RTDB rules endpoint returns HTTP 403.

### Pilot deployment and rollback runbook

The professor-facing Preview should use the existing shared Firebase project and a separate Vercel project. No Firebase configuration or deployed rules are changed by this workflow.

#### Shared Firebase authorization check

1. Ask a Firebase administrator to export the current RTDB and Firestore rules, or authorize a Firebase CLI account with read access to `stela23-f9a52`.
2. Compare the active rules with the operations the feature uses: reads of `quizzes/$subjectKey`, writes to `question_tagging/$subjectKey/$quizId/$questionId` and `taxonomy/$subjectKey`, and creation of a student's own `quiz_submissions` document.
3. If a rule is missing, merge only the minimum path-specific rule into the active rules. Do not deploy either Emulator candidate as a replacement for the shared rules. Re-run the Emulator tests against a merged rules export before any rules deployment.

#### Separate Vercel Preview after rule and account checks

1. The separate `stela-professor-pilot` Vercel project is created; do not use `stela_ai` or `stela-exec-backend`. The app's checked-in default Firebase options point to `stela23-f9a52`.
2. The Preview environment variable `CODE_EXEC_ENDPOINT` is set to `https://stela-exec-backend.vercel.app/execute`. Do not set `ISTELA_ASSESSMENT_PILOT_BUILD` or alternate `PILOT_FIREBASE_*` values for this shared-project deployment.
3. GitHub Actions secrets `VERCEL_TOKEN`, `ASSESSMENT_PILOT_VERCEL_ORG_ID`, and `ASSESSMENT_PILOT_VERCEL_PROJECT_ID` are configured for the new Vercel project. The workflow refuses the existing production project ID.
4. The feature branch has been deployed to Preview. Before any live writes, confirm active Firebase rules and use an authorized professor/test-student account pair. Do not run `firebase deploy` from this branch until the active rules have been merged and reviewed.
5. The Preview root was opened in a browser and the Flutter app shell/canvas loaded. Vercel SSO behavior and professor sign-in, quiz editor, tag save/reopen/stale review, student attempt/evidence, and unauthorized-denial workflows remain unverified. Record those results before presenting the workflow as tested.
6. Roll back by restoring the previous Vercel Preview deployment. This does not affect the existing production Vercel URL or Firebase data.

The separate Preview deployment is verified as built and deployed, but authenticated faculty/student workflows and direct professor accessibility are not verified; the manifest request redirected to Vercel SSO. Software and Emulator tests do not establish research validity.

### Professor-demo UI checkpoint

The faculty question editor now presents an explicit **Tag concepts & skills** action, changes it to **Review stale tags** when the question fingerprint no longer matches, and labels the confirmation action **Reconfirm tags**. The student results screen shows confirmed concepts/skills and earned/possible marks on each question, in addition to the quiz-scoped competency summary. Unreviewed, stale, fingerprint-mismatched mappings and suggested skills are not shown as verified question evidence.

Validation for this checkpoint:

- `cd frontend && flutter test test/assessment_feedback_service_test.dart test/assessment_tagging_service_test.dart test/assessment_tagging_test.dart test/assessment_tagging_ui_test.dart test/taxonomy_service_test.dart test/widget_test.dart` — **31 passed**.
- Legacy quiz serialization strips tag/cache-only fields while preserving images and unknown question properties; covered by `assessment_tagging_service_test.dart`.
- `cd frontend && flutter build web --release --dart-define=CODE_EXEC_ENDPOINT=https://stela-exec-backend.vercel.app/execute` — **build succeeded** using the checked-in shared Firebase options. `build/web/version.json` reports version `8.0.0`, build number `8`. Flutter reports the existing WebAssembly dry-run incompatibility from `universal_html`/`dart:html`; normal web output completes.
- `cd frontend/rules_tests && npm run test:build-config && npm run test:claims` — **11 passed**, including ordinary Preview isolation and pilot-only Preview enforcement.
- `cd frontend/rules_tests && npm run test:emulator` with Android Studio Java 21 on PATH — **22 passed** across the isolated RTDB and Firestore candidate rules.
- Candidate Emulator tests do not establish the live project's rules. `firebase login:list` reports no authorized accounts, and the unauthenticated rules endpoint returns HTTP 403.

No separate professor Preview URL exists yet. Vercel CLI currently lists only `stela_ai` and `stela-exec-backend`; a third, separate Preview project is needed. A new Firebase project is not required. Before real faculty/student smoke testing, an authorized operator must confirm the active shared rules and provide an authorized professor/test-student account pair and a safe test quiz. The test-only rules are not production rules and must not be deployed as a replacement.
