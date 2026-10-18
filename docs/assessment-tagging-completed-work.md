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
| RTDB rules use trusted role claims and restrict assigned faculty to one subject key | Emulator-verified | The allow/deny matrix passed in GitHub Actions run `39118782771`, including assigned/cross-course faculty, missing claims, student read/write restrictions, and admin/steward access. |
| Trusted Admin SDK role/course claim provisioning | Unit-tested | A guarded CLI tool supports explicit pilot-account claims via ADC in `frontend/rules_tests/provision_assessment_claims.mjs`; it does not infer roles from client-created Firestore documents. The institution must still approve the role/course roster and an authorized operator must apply claims. |
| Rules denial/allow matrix in Firebase Emulator | Emulator-verified | `test_assessment_tagging_rules.yml`, run `39118782771` on commit `ee6ec0294ef50ba9d42f1a6f2bf029ec9728616e`; CI uses Java 21. The local emulator command still cannot start because Java is unavailable locally. |
| Pilot access to legacy quizzes and persisted student attempts | Blocked | `database.rules.json` defaults to deny and defines no `/quizzes` access; `firestore.rules` has no `quiz_submissions` write rule. The metadata allow/deny matrix does not test these legacy application paths. A pilot-only policy and corresponding Emulator coverage are required before those rules can be deployed. |
| Compatibility with other applications on the existing shared Firebase project | Blocked | The draft feature rules default-deny paths not listed in the rules file and would block existing clients if deployed there. Do not deploy them to `stela23-f9a52`; the pilot must use its own Firebase project. Existing shared rules and cross-application behavior were not changed or verified. |
| Existing quiz, both Excel imports, images, editing, randomization and old-client compatibility | Blocked | Unit coverage does not yet prove both import workflows, historical payload behavior, image flows, answer alignment, or repeated-import behavior end to end. |
| Pilot build, deployment, smoke test and rollback record | Blocked | No dedicated pilot Firebase/Vercel project or pilot accounts are configured. No remote deployment has been made. |
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

1. Obtain the institution-approved staging role/course roster, then have an authorized Firebase Admin operator apply one-course claims with the guarded Admin SDK utility. The pilot contract currently uses a single `assessmentSubjectKey`; multi-course claim semantics are not implemented.
2. Run and fix the RTDB allow/deny matrix in the Firebase Emulator, including legitimate faculty, cross-course faculty, students, admins/stewards, missing claims, and private student evidence.
3. Add end-to-end tests for faculty tag/save/reopen/edit/stale recovery, student randomization/scoring/evidence, both Excel creation flows, images, and old quiz records.
4. Run the established Flutter build/test gates and a compatibility review against supported legacy payloads.
5. Only after the above gates, use an approved staging Firebase project and staging accounts for deployment and smoke tests; record commit and rollback steps. Do not deploy these draft rules to production.
6. Keep expert review, pilot approval, ethics, and empirical diagnostic validation as separate external gates.

### Current continuation

The taxonomy editor now reads the Firebase registry instead of silently using a fixed pilot list. An absent registry is returned as empty and is not automatically seeded or written; taxonomy persistence occurs only after a faculty member explicitly creates or archives a node. Sibling uniqueness now normalizes case/whitespace within scope, reparent checks destination collisions, and course-specific search results are prioritized while shared records remain visible.

The chosen authorization direction is Firebase Auth custom claims issued only by a trusted Admin SDK process. The draft rules require `assessmentFaculty: true` with an exact `assessmentSubjectKey` for faculty writes, or `assessmentAdmin: true` / `taxonomySteward: true` for stewarded cross-course writes. Students may read reviewed metadata and write only their own evidence. Claims are not provisioned by the app. A guarded operator CLI at `frontend/rules_tests/provision_assessment_claims.mjs` defaults to dry-run, requires exact project confirmation before applying, preserves unrelated claims, and can grant/revoke only the managed assessment claims. The existing UI resolves roles from Firestore, but both faculty signup flows write `userRole: 'Faculty'` from the client, so that field is not an authoritative approval source for privileged claims. Existing subject records are also created by their owning signed-in user. The CLI must only be used after the institution approves the account-to-course roster; missing claims deny protected writes.

### Next implementation target

The emulator allow/deny matrix still needs a Java 17+ runtime available to Firebase CLI. The institution must approve the staging faculty/admin/student roster and course key; an authorized operator can then use the guarded claims CLI. Historical review and broad old-client compatibility remain separate checks; no staging deployment is safe until authorization and compatibility gates pass.

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

Validation this increment: `flutter test test/assessment_feedback_service_test.dart test/assessment_tagging_service_test.dart test/assessment_tagging_test.dart test/taxonomy_service_test.dart test/widget_test.dart` passes (28 tests), and `flutter build web --release` succeeds (with WebAssembly dry-run incompatibility notices from `universal_html`/`dart:html`). New regression coverage verifies that sibling tags contribute a question only once to their shared ancestor and that missing taxonomy data does not invent parent evidence. The rules test JavaScript passes `node --check`, and `npm ls --depth=0` confirms the pinned direct dependencies are installed. `npm run test:emulator` is blocked before tests start because Firebase CLI cannot spawn `java -version`; no rules pass is claimed. `npm audit` reports 12 test-tool dependency advisories (8 high, 4 moderate, 0 critical); these are in the rules-test toolchain, not the Flutter production dependency set. Non-forced `npm audit fix` could not remediate them and recommends breaking dependency changes. Targeted `flutter analyze` exits with 100 warnings/info diagnostics (2 warnings and 98 infos, no error diagnostics); because the files were already dirty before this continuation, there is no clean analyzer baseline to attribute those findings to.

### Pilot deployment and rollback runbook

No pilot Firebase/Vercel projects or pilot credentials are configured yet. This is an internal pilot, not a formal staging or general production release. After the Emulator and core workflow checks pass:

#### Pilot Firebase setup

1. Create a separate Firebase project for the professor-facing pilot. Never select the existing `stela23-f9a52` project.
2. Enable Firebase Authentication email/password sign-in and create one pilot faculty account and one pilot student account.
3. Initialize Realtime Database, Firestore, and Storage in the pilot project. Record its project ID and RTDB URL/region.
4. Register a Web app and copy its public Firebase web configuration into both (a) the Vercel Preview environment variables and (b) GitHub Actions Variables for pilot build validation. Required names: `PILOT_FIREBASE_API_KEY`, `PILOT_FIREBASE_APP_ID`, `PILOT_FIREBASE_MESSAGING_SENDER_ID`, `PILOT_FIREBASE_PROJECT_ID`, `PILOT_FIREBASE_DATABASE_URL`, `PILOT_FIREBASE_AUTH_DOMAIN`, `PILOT_FIREBASE_STORAGE_BUCKET`; `PILOT_FIREBASE_MEASUREMENT_ID` is optional. Set `ISTELA_ASSESSMENT_PILOT_BUILD=true` only in the dedicated pilot Vercel project's Preview environment; ordinary Preview builds do not use pilot Firebase settings. Also set `CODE_EXEC_ENDPOINT` in the dedicated Vercel project's Preview environment and `PILOT_CODE_EXEC_ENDPOINT` as a GitHub Actions Variable.
5. Confirm which pilot account is faculty and its subject key. Use a trusted Admin SDK operator (Application Default Credentials with minimum necessary IAM) to provision its custom claims using the guarded CLI. Never put service-account JSON in the repository or send it in chat.
6. The Emulator CI job requires Java 17+; the GitHub Actions workflow provisions this runtime.

#### Pilot deployment after release gates pass

1. Create a separate Vercel project for the pilot under the authorized Vercel team. Do not use the project configured for `https://stelaai.vercel.app/`. Set its Preview environment variables listed above.
2. Configure these GitHub Actions secrets: existing `VERCEL_TOKEN`, `ASSESSMENT_PILOT_VERCEL_ORG_ID`, and `ASSESSMENT_PILOT_VERCEL_PROJECT_ID` for the separate pilot Vercel project. The workflow explicitly refuses the current Vercel production project.
3. Use the confirmed pilot Firebase project ID; inspect the intended Firebase project before any deployment. After Emulator tests pass, deploy only the RTDB rules to that project:

   ```text
   cd frontend
   firebase deploy --only database --project <pilot-firebase-project-id>
   ```

   Use an authorized Firebase account, the exact pilot project ID, and never deploy rules to `stela23-f9a52`.
4. For each approved pilot account, preview claim changes first from `frontend/rules_tests/`:

   ```text
   node provision_assessment_claims.mjs <pilot-firebase-project-id> <firebase-auth-uid> faculty <subject-key>
   node provision_assessment_claims.mjs <pilot-firebase-project-id> <firebase-auth-uid> faculty <subject-key> --apply --confirm-project=<pilot-firebase-project-id>
   ```

   The operator must authenticate with Application Default Credentials or an approved service account outside the repository. Ask each account to refresh its Firebase ID token after claims change.
5. Push the feature branch after its GitHub variables and Vercel pilot secrets are configured. The workflow runs the rules Emulator tests and Flutter regressions/build before deploying to the separate Vercel Preview project. Confirm the resulting Preview URL and Firebase project identity before sharing it with the professor.
6. Run faculty sign-in, tag/save/reopen/edit, student attempt/evidence, and denied-user smoke checks; record the deployed Git commit and Firebase project ID.
7. Roll back by restoring the prior Vercel Preview deployment and re-deploying the previously reviewed pilot RTDB rules. Keep the exact prior rules artifact with the pilot release record.

No pilot deployment or scientific validation is claimed. The remaining pilot gates are approved pilot Firebase/Vercel projects and accounts, deployed core-workflow smoke checks, and review of the test-tool dependency audit. Software tests do not establish research validity.

### Professor-demo UI checkpoint

The faculty question editor now presents an explicit **Tag concepts & skills** action, changes it to **Review stale tags** when the question fingerprint no longer matches, and labels the confirmation action **Reconfirm tags**. The student results screen shows confirmed concepts/skills and earned/possible marks on each question, in addition to the quiz-scoped competency summary. Unreviewed, stale, fingerprint-mismatched mappings and suggested skills are not shown as verified question evidence.

Validation for this checkpoint:

- `cd frontend && flutter test test/assessment_feedback_service_test.dart test/assessment_tagging_service_test.dart test/assessment_tagging_test.dart test/assessment_tagging_ui_test.dart test/taxonomy_service_test.dart test/widget_test.dart` — **31 passed**.
- Legacy quiz serialization strips tag/cache-only fields while preserving images and unknown question properties; covered by `assessment_tagging_service_test.dart`.
- `cd frontend && flutter build web --release` with non-live dummy pilot Dart defines — **build succeeded**. Flutter reports the existing WebAssembly dry-run incompatibility from `universal_html`/`dart:html`; the normal web release build completes.
- `cd frontend/rules_tests && npm run test:build-config && npm run test:claims` — **11 passed**, including ordinary Preview isolation and pilot-only Preview enforcement.
- `cd frontend/rules_tests && npm run test:emulator` remains blocked locally because Java is not installed; the rules Emulator suite **passed in GitHub Actions run `39118782771`** with Java 21.
- On the pushed checkpoint, GitHub Actions run `39120435959` passed the rules Emulator step and focused Flutter test step; it stopped at the pilot web-build configuration guard because `PILOT_CODE_EXEC_ENDPOINT` and pilot Firebase variables are not configured. Deployment was skipped.

No pilot URL is available yet. A dedicated pilot Firebase project and a separate Vercel project, authorized test accounts, and their configuration/access are required before deployment and real faculty/student smoke testing. The current Flutter build used dummy values only and did not connect to Firebase. The checked-in rules currently protect the new metadata paths but are not a complete access policy for the quiz and Firestore attempt paths required by the app; do not deploy them to any environment until those pilot paths have a reviewed, Emulator-tested policy.
