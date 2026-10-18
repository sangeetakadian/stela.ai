# Hierarchical Assessment Tagging and Evidence Feedback

**Status:** Proposed functional specification and implementation plan
**Scope:** Source-informed design; no feature implementation, live Firebase validation, or production-data inspection is claimed here.
**Primary release scope:** One B.Tech course, one unit, MCQ pilot.
**Binding constraint:** Existing database records and the current behavior of previously released app versions must remain compatible. Database compatibility is a release-blocking requirement, not a best-effort goal.

## 1. Purpose and research boundary

ISTELA should let faculty describe the concepts a question covers and, separately, the observable skills it actually assesses. Students may then receive cautious, traceable feedback based on scored question evidence.

The initial work is a research prototype, not a validated measurement instrument, a general-purpose LMS, or proof of improved learning. The PhD pilot is limited to one institution-approved B.Tech course, a small expert-defined skill set, and a manageable set of questions. Broader branch rollout, longitudinal proficiency claims, and interventions are future work.

Research question: with sparse and potentially overlapping faculty mappings, can an explainable method infer limited engineering competencies more defensibly than aggregate marks or simple topic percentages, while reporting coverage and uncertainty and abstaining when evidence is inadequate? This is an empirical question; no improvement is assumed.

### Research work packages

| Package | Purpose | Deliverable | Exit evidence |
|---|---|---|---|
| WP1 — Measurement foundation | Establish reviewed mappings and a safe vertical slice | One-course concept tree, small skill catalogue, faculty tagging, legacy-compatible quiz flow, provisional feedback | Pilot quiz passes end to end; experts can review mappings; insufficient evidence is represented |
| WP2 — Trustworthiness study | Test whether the diagnostic evidence is reliable and useful | Pre-registered metrics, baselines, mapping agreement, stability, coverage and uncertainty analyses | Reproducible comparisons and reported limitations, including negative results |
| WP3 — Thesis synthesis | Support defensible conclusions | Single-course case study, methods, results, failure modes, ethics and limitations | Supervisor-reviewed report with claims proportional to evidence |

Novelty requires a targeted literature review (including Q-matrix/cognitive diagnosis, outcome-based education, knowledge tracing, and uncertainty-aware assessment). It is not established by implementing tagging software.

## 2. Scope and exclusions

### WP1 pilot

- One faculty-approved B.Tech course and unit; select them only after supervisor, faculty, and data-availability review.
- MCQs first. Existing quiz-taking, scoring, authoring, images, question order, and both Excel quiz-creation flows remain supported.
- Searchable, arbitrarily deep concept taxonomy; separate, curated skill catalogue.
- Faculty can tag new and edited pilot questions with multiple concepts, identify a primary concept, explicitly confirm assessed skills, and save/reopen without losing tags.
- Deterministic, single-quiz concept feedback tied to the actual scored question identity. Skill feedback is shown only when the evidence policy is met; otherwise show “Insufficient evidence” or “Not assessed.”
- No generative AI is required.

### Later work, not WP1 exit criteria

1. Historical-question export, review workbook, and dedicated tag-only patch importer.
2. All-branch taxonomy, institution-wide governance, bulk tagging and taxonomy lifecycle tooling beyond what the pilot needs.
3. Longitudinal student profiles, faculty coverage views, rubric-based coding/subjective/lab evidence, AI-generated phrasing, adaptive assessment, and learning-impact studies.

The current Excel upload creates a new quiz. It must remain a quiz-creation flow and must never be reused as a historical tag-update importer.

## 3. User roles and core workflows

### Roles

- **Taxonomy steward / institution administrator:** controls shared roots, published skills, cross-course governance, merges, retirement, and audit.
- **Assigned faculty:** browses shared taxonomies, creates concepts within authorized course scope, tags questions they may edit, and proposes new shared skills for review.
- **Student:** reads approved labels and evidence-backed feedback; cannot create or edit taxonomy.
- **Import service/operator (future phase):** performs separately authorized, validated, audited tag-only updates.

Authorization must be enforced by Firebase security rules or a trusted service, not merely by hiding UI controls. Current deployed rules and role data must be inspected before implementation; this document does not assert that they currently provide these permissions.

### Faculty taxonomy and tagging flow

`Faculty Dashboard → Manage Topics & Skills → choose assigned course → browse/search Concepts or approved Skills → add an authorized concept child or propose a skill`

`Create/Edit Quiz → question → Topics & Skills → search full paths → select concepts → review skill suggestions → explicitly confirm skills or explicitly select none → save → reopen and verify`

Concept creation is available inline from the question editor using the same registry and validation as the management screen.

### Student flow

`Take existing quiz → existing grading → result → resolve reviewed tags for the actual scored questions → show scoped concept evidence and cautious next steps`

No feedback may claim that a student lacks every skill associated with one incorrectly answered multi-tagged question.

## 4. Functional requirements

### 4.1 Separate academic structure, concepts, and skills

- Existing course/unit records remain the academic structure and are not replaced by a new taxonomy.
- Concepts represent technical knowledge (for example, `Digital Electronics / Sequential Circuits / Flip-Flops / JK Flip-Flop`).
- Skills represent separately defined, observable capabilities (for example, application or quantitative reasoning).
- Concept and skill hierarchies are separate, single-parent trees of arbitrary depth. A node has a stable canonical ID; a displayed breadcrumb is derived from its ancestors.
- A shared concept may be associated with multiple courses without cloning it or giving it multiple parents. A question may reference multiple concepts.
- A concept-parent relationship does not imply that an item assesses every ancestor or suggested skill.

### 4.2 Taxonomy management

Each node should support, as appropriate, a stable ID, kind, name, parent ID, scope, course associations, status, aliases, definition, creator/approver, timestamps, and version. A skill also requires observable-evidence examples and suitable assessment methods before it is published for assessment use.

- Search matches names, aliases, and ancestors, displays the full path and kind, and prioritizes the current course without hiding authorized shared results.
- Normalize names for sibling uniqueness within the same parent and scope. Same names under different parents are allowed and must remain distinguishable by path.
- Reject blank names, invalid or unauthorized parents, kind mismatches, and cycles. Concurrent creation must not silently create duplicate siblings.
- Rename and valid reparent operations preserve IDs and question references. Shared-tree changes require steward authorization and a preview of impact.
- Retire/archive instead of deleting referenced nodes. Preserve historical labels/references and prevent new selection where appropriate.
- Merge requires a steward-reviewed impact preview, a retained alias/redirect, an audit record, and a rollback path.

The WP1 implementation may deliver only the taxonomy operations needed for the pilot. Full governance is a later product increment.

### 4.3 Question tags and skill suggestions

Question-level metadata has distinct states:

- **Concept association:** one or more concept IDs, with an optional primary concept for the pilot’s evidence attribution.
- **Suggested skill:** a non-authoritative suggestion generated from a concept default, with source/provenance.
- **Assessed skill:** a faculty-confirmed skill that the question actually elicits evidence for.
- **Proposed mapping:** unreviewed/imported suggestion that is excluded from diagnostics.

When a concept is selected, display de-duplicated skill suggestions and their source; inherited suggestions must be labeled as inherited. Faculty must explicitly confirm, edit, reject, or deliberately choose no assessed skills. A zero-skill choice is “Not assessed,” never a zero score.

Changing concepts or concept defaults must not silently replace previously confirmed question-level skills. Flag a potentially stale mapping for faculty review instead. Proposed or unreviewed tags never enter student analytics.

The question editor and every save path must preserve all existing question content and future/unknown fields. This includes question type, wording, choices and order, answer key, marks, image configuration, coding fields, test cases, and metadata. No new tag is mandatory to open, play, or edit a legacy untagged question.

### 4.4 Evidence and feedback

The evidence chain is:

`course/unit → reviewed question mapping → student attempt for that question → existing scored outcome → eligible evidence set → deduplicated aggregation → scoped feedback`

- Only reviewed mappings and valid scored outcomes contribute.
- For a directly assessed concept or skill, performance is `sum(earned marks) / sum(possible marks)` over eligible items. Show item/attempt counts and scope.
- For a single-question pilot, label feedback “Based on this quiz” and report the exact count. Do not claim persistent student ability.
- When rolling child evidence to a parent, count each question once per ancestor.
- Prefer the primary assessed concept for categorical feedback. Related concept presence alone does not establish that a wrong response indicates weakness in every concept.
- A proposed product safeguard is to abstain from a skill rating below five distinct assessed items. This threshold is configurable and is not evidence of psychometric validity.
- Handle zero attempts and zero denominators explicitly. “Not assessed,” “Insufficient evidence,” and “Mixed evidence” are valid results.
- Keep current quiz marks and result behavior unchanged. Client-side quiz scoring is advisory evidence for this prototype, not an institutional-grade verified grade.
- Use deterministic, source-grounded practice suggestions only. Do not infer teamwork, leadership, lab proficiency, research integrity, or broad cognitive ability from ordinary MCQs.

### 4.5 Existing-question review — later, one question at a time

Do not bulk-label the historical bank in the pilot. When the pilot and database
compatibility gates pass, the preferred first backfill workflow is a
faculty/operator-led review queue that fetches and handles **one existing
question at a time** directly from the authorized Realtime Database:

1. Select the next unreviewed question from a bounded course/unit/quiz scope.
   Fetch only that question and the minimum display context needed. Do not
   export the question bank or expose answer keys, hidden grading data, or
   solution code unless the authorized reviewer explicitly needs and may see
   them.
2. Display its source location, quiz/question identity, current content,
   current metadata (if any), and any existing tags. Ask the reviewer to
   choose concepts, primary concept, and explicitly assessed skills, or mark
   it uncertain/skip. Suggestions may assist but are never accepted
   automatically.
3. Show a clear before/after preview. No database write occurs until the
   authorized reviewer explicitly confirms that question's proposed metadata.
   Skip/uncertain leaves stored tags unchanged.
4. Immediately before applying, re-read the source question and compare its
   stable identity and canonical fingerprint/revision with the one reviewed.
   If it changed, moved, disappeared, or matches ambiguously, stop for that
   item; do not guess or write tags.
5. Write only the confirmed metadata to the approved additive sidecar path;
   never rewrite the legacy quiz/question arrays. Re-read and verify the
   sidecar write before advancing to the next question.
6. Record reviewer, timestamp, source identity/revision, decision, tag IDs,
   result, and any conflict in an access-controlled audit/progress record.
   Support safe resume after interruption without repeating or applying an
   unconfirmed decision. Re-confirm if the source revision has changed.

This sequential process is feasible if the operator has authorized database
access, the security rules permit the metadata-only write, question identity
can be validated, and there is an audited recovery path. Do not connect an
assistant or script to production writes until those prerequisites and the
explicit per-question confirmation UX are tested. It is intentionally not
automated labeling and not the existing “Upload Excel” quiz-creation flow.

Never identify a question from text alone. If identity or content is stale,
missing, duplicated, or ambiguous, record a conflict and do not tag it.
Historical Excel export/import can be considered later if this guided review
approach proves insufficient; it is not a prerequisite for the first backfill.

## 5. Database backward-compatibility contract — release blocker

The current source writes quiz records under Realtime Database `quizzes/<subject>/<unit>/<quizId>` and mirrors question arrays in `questions` and `facultyQuestions`. The faculty save path constructs a quiz map and calls `set`; the MCQ edit path reconstructs a smaller map and drops unknown fields. Therefore **putting tagging data only inside the existing quiz/question maps is not an acceptable persistence design** until old-writer behavior has been proven safe.

### Mandatory compatibility rules

1. **Do not rename, move, remove, repurpose, or change the type/meaning of any existing database path or field.**
2. **Do not require any new field or schema version for existing clients to read or write quizzes.** Old untagged records remain valid.
3. **Do not make metadata embedded in a question map the sole copy of tags or stable identity.** A previous app version can rebuild that map and remove unknown keys.
4. Prefer an **additive, separately namespaced metadata path** (for example, a versioned question-tagging subtree keyed by quiz and stable question IDs) and separate taxonomy paths. Confirm exact names, database rules, indexing, and access controls during the source/rules audit before implementation.
5. New clients treat absent metadata as the legacy state and continue the existing quiz flow. Readers must tolerate unknown fields and partial/missing sidecar metadata.
6. Tag writes update only the new metadata namespace. They must not rewrite `questions`, `facultyQuestions`, answer keys, marks, quiz identity, or question order merely to save tags.
7. If compatibility requires an optional additive identity hint inside a question, treat it only as a cache/hint. It must not be required for older clients, and the authoritative mapping must remain recoverable and validated outside the legacy record.
8. Validate sidecar-to-question association against a stable ID where available and a canonical fingerprint/snapshot of identity-bearing fields. On stale, duplicate, missing, or ambiguous matches, abstain and require review; never attach evidence to a “best guess” question.
9. A legacy app edit/re-save must not erase the canonical sidecar tags. If its question edits invalidate the sidecar association, preserve the metadata but mark the association stale/unresolved and exclude it from diagnostics until repaired. Legacy quiz behavior must still work.
10. Use additive, lazy writes; no mass migration or rewrite of old quiz records is required for the pilot. Do not deploy a destructive rollback or delete the new metadata namespace during app rollback.
11. Inspect production-equivalent Firebase rules and prove authorized access before enabling writes. Students must not gain write access to taxonomies/tags or read access to protected answer keys by virtue of this feature.
12. Roll out with a feature gate. Enable tagging only after compatibility, rules, backup/restore, and CI gates pass. Deploy code so old and new app versions can coexist; rollback the UI/service independently without rolling back or corrupting legacy data.

### Required compatibility matrix

| Reader/writer | Legacy quiz without tags | Quiz with sidecar tags | Save behavior |
|---|---|---|---|
| Previous released app | Opens, lists, plays and grades normally | Ignores new metadata and continues to function | Existing edits retain current semantics; they cannot delete sidecar data |
| New app, no sidecar present | Opens and edits without requiring tags | N/A | Adds metadata only when faculty explicitly tags |
| New app, valid sidecar | Opens and displays tags | Reads/edits tags without changing legacy fields | Metadata-only update; unrelated quiz content remains byte/semantically unchanged |
| New app, stale/ambiguous sidecar | Legacy quiz remains usable | Does not display/apply an unverified mapping as fact | Marks for review; no automated remapping or evidence use |

Before finalizing the data model, test actual previous-version behavior (or an exact legacy-writer fixture) against the proposed paths. A design that merely assumes old clients ignore unknown keys does not satisfy this contract.

## 6. Implementation and test-driven execution plan

**Working rule:** For every increment, first write a failing test for the observable requirement, run it to demonstrate the gap, implement the smallest change, rerun the focused test, then run the relevant regression set. Do not mark an increment complete based only on source review. Add each new regression case to the automated pipeline in the same change that introduces the behavior.

### Progress board

The same work items are tracked in the session task list. Update a task to
**In progress** only when its work starts, **Done** only when its exit evidence
exists, and **Blocked** when a named decision or prerequisite prevents progress.
Keep this board synchronized when implementation begins.

**Overall: 0/12 work items complete.** Work item 1 is blocked pending access to
the current Realtime Database rules and verification of an actual previous
client; feature implementation has not started.

| # | Work item | Status | Completion evidence |
|---|---|---|---|
| 1 | Legacy database and previous-client compatibility audit | Blocked | Current paths/rules/writers documented; old-writer behavior understood |
| 2 | Approve pilot course, skills, owners, and evidence policy | Pending | Faculty/supervisor decisions recorded |
| 3 | Add legacy regression fixtures and baseline tests | Pending | Baseline tests run and results recorded |
| 4 | Define additive sidecar metadata contract and feature gate | Pending | Paths/rules/conflict policy reviewed; no legacy schema changes |
| 5 | Test legacy/new-client coexistence and authorization | Pending | Compatibility matrix passes, including old-client re-save |
| 6 | Implement taxonomy services test-first | Pending | Taxonomy and permission tests pass |
| 7 | Implement faculty tagging and explicit skill confirmation | Pending | Save/reopen/edit and suggestion-semantics tests pass |
| 8 | Implement evidence aggregation and feedback test-first | Pending | Attribution, deduplication, threshold, and abstention tests pass |
| 9 | Run pilot integration and require checks in CI | Pending | Full WP1 regression/build gates pass before deployment |
| 10 | Evaluate trustworthiness (WP2) | Pending | Predefined, reproducible evaluation completed and limitations reported |
| 11 | Synthesize research findings (WP3) | Pending | Supervisor-reviewed report distinguishes tested results from hypotheses |
| 12 | Review existing questions one at a time (later backfill) | Pending | Each confirmed sidecar write is source-checked, explicitly approved, verified, and auditable; skips/conflicts make no data changes |

**Audit notes:** Checked-in Flutter source stores quizzes under RTDB
`quizzes/<subject>/<unit>/<quizId>` and mirrors `questions` /
`facultyQuestions`. Quiz creation/editing uses whole-record `set`; the MCQ
editor rebuilds question maps and drops unknown fields; moving a quiz removes
the old record and writes a new key. The quiz reader prefers
`facultyQuestions`, falling back to `questions`. An older checked-in source
snapshot (`904ffbc`) has the same whole-record edit and MCQ reconstruction
behavior, but this does not establish what every deployed/installed binary
does. The checked-in Firebase config declares Firestore, Storage, and Hosting,
not RTDB rules or an RTDB emulator; its rules file is Firestore-only. Firebase
CLI is not installed/on PATH. The production RTDB was not read or modified.
Thus the sidecar approach is a strong design candidate, but its rules and
actual prior-client coexistence are unverified and remain blocking gates.

The frontend Vercel workflow currently runs Vercel pull/build/deploy without
Flutter analyzer, unit/widget, or web-build preflight gates. Adding those
required checks belongs to the CI work item. No tagging feature or production
data was modified. A separate full-RTDB backup/copy utility is documented in
[rtdb-project-migration.md](rtdb-project-migration.md); its 14 tests use
mocked HTTP only, and execution remains blocked until Google credentials are
configured and the backup/destination are reviewed.

| Step | Test-first implementation work | Exit gate |
|---|---|---|
| 0. Source, rules, and compatibility audit | Capture current database paths, RTDB rules, old/new serializer shapes, mirrored-list behavior, question types, Excel parsers, question shuffling/scoring identity, and deployed app compatibility. Create a versioned legacy payload/writer fixture and baseline regression tests before edits. | Data design reviewed; no unverified production-data assumptions; legacy baseline passes. |
| 1. Persistence contract and pure models | Tests for absent metadata, additive taxonomy/tag models, stable IDs, deterministic fingerprints, stale/ambiguous identity handling, forward-compatible parsing, and preservation of unknown fields. Select isolated sidecar layout and rules. | Contract has automated tests; old quiz payload remains unchanged by metadata operations. |
| 2. Taxonomy service | Tests first for hierarchy paths, arbitrary depth, scoped search, aliases, sibling normalization, duplicate/concurrent-create conflict, authorization, parent-kind mismatch, cycle rejection, rename/reparent ID stability, and archive behavior. Add taxonomy storage only after rules pass. | Service and rules tests pass; unauthorized writes are denied. |
| 3. Faculty tagging and suggestions | Widget/service tests for multi-concept selection, primary concept validation, suggested vs inherited provenance, explicit skill confirmation, reject/clear/zero-skill, proposed-vs-reviewed state, stale suggestion warning, and create-inline/cancel behavior. | Tagging metadata survives save/reopen/edit and is isolated from legacy quiz fields. |
| 4. Result evidence engine | Pure tests for question/score identity under question and option shuffling; direct vs related tags; reviewed-only evidence; mark denominators; parent roll-up deduplication; evidence thresholds; no-attempt/zero-denominator; abstention and one-question scope. | Feedback is deterministic, traceable to eligible scored questions, and never overstates multi-tag evidence. |
| 5. Pilot UI and integration | End-to-end tests for authorized faculty setup → create child → tag MCQ → save/reopen/edit → student attempt → result. Run existing quiz, image, subjective/coding-map, auth/role and both Excel creation regressions. | WP1 acceptance met on one approved course without legacy behavior changes. |
| 6. CI and rollout gate | Make locked dependency resolution, analyzer, unit/widget tests and web build required before frontend deployment; run backend tests before backend image/deployment. Add tests to the same jobs as they are authored. Add Firebase Emulator integration tests for rules/read-write compatibility and sidecar behavior; production checks are read-only until separately approved. | Failed tests/build block deployment; green workflow and documented compatibility evidence required before enabling feature. |
| 7. WP2 research evaluation | Freeze definitions and evaluation plan before comparative analysis. Independently map a subset with at least two experts where feasible; adjudicate disagreement; compare overall marks, naive topic percentages, and proposed interpretable method; assess coverage, calibration/uncertainty, abstention, stability and sensitivity. | Reproducible protocol, metrics, confidence intervals/limitations, and negative findings reported. |
| 8. WP3 synthesis | Produce single-course case study, implementation/test evidence, ethics/privacy, failure modes, reproducible analysis and supervisor review. | Claims distinguish designed, implemented, tested, and empirically supported results. |

Steps 0–6 implement the focused pilot. Historical tagging and longitudinal product extensions remain separate scoped initiatives and cannot be pulled into WP1 without an explicit scope decision.

## 7. Required test suite and pipeline growth

### Must-have test cases

- **Legacy database compatibility:** legacy fixture reads; previous-version create/edit/re-save still lists, opens, plays, and grades; sidecar tags survive; question paths, answer keys, marks, and ordering remain intact.
- **Lossless editing:** legacy untagged MCQ, image, subjective and coding payloads survive open/save, including unknown fields, image settings, test cases, options and marks.
- **Import regression:** six-column MCQ and header-based MCQ/subjective/coding workbooks still create new quizzes; multiline data is retained; tag columns are optional; no historical update route invokes quiz creation.
- **Metadata safety:** absent, partial, stale, duplicated, mismatched, reordered, or ambiguous metadata yields safe abstention; fingerprints never silently attach a tag to another question.
- **Taxonomy:** arbitrary depth, full breadcrumb, alias/ancestor search, cross-course association, duplicate sibling prevention, same label on different branches, authorization, cancellation, cycle prevention, rename/reparent, archive, and stable references.
- **Suggestion semantics:** direct/inherited provenance, de-duplication, explicit confirmation, reject/clear/none, defaults changing without rewriting confirmed tags, and proposed tags excluded from scoring.
- **Evidence correctness:** shuffled question/options, actual question-score alignment, direct/primary attribution, related concept caution, parent roll-up deduplication, threshold, insufficient evidence, no attempts, and denominator edge cases.
- **Permissions/security:** student read-only taxonomy, unauthorized faculty denied outside assigned scope, answer-key/solution protection, and restricted export.
- **Rollout:** old and new clients coexist; feature-off behavior is unchanged; a failed CI gate prevents deploy; rollback does not delete or rewrite the sidecar.

### Pipeline policy

- Add automated coverage whenever behavior is added; do not postpone tests to a final hardening pass.
- Frontend deployment requires locked dependency resolution, `flutter analyze`, `flutter test`, and production web build to pass first.
- Backend deployment requires the focused backend test suite before Sandbox image build and deployment.
- Firebase Emulator tests cover security rules, legacy and sidecar reads/writes, and concurrent/idempotent operations. Do not point destructive automated tests at production Firebase.
- Keep a small, explicit manual checklist for browser/Firebase-dependent flows that cannot be reliably automated; record run date, app version, environment, and result.
- Test failures, skipped integration tests, and unrun checks must be visible; never report them as passing.

## 8. WP1 acceptance criteria

WP1 is complete only when all are true:

1. Faculty can create an authorized concept hierarchy and tag a pilot MCQ with multiple canonical concepts and explicitly confirmed assessed skills.
2. Save/reopen/edit preserves tags, all question content, and every unrelated legacy field.
3. Student feedback uses the scored result for the correct question identity, displays exact count/scope, deduplicates ancestor evidence, and abstains where evidence is insufficient.
4. An untagged legacy quiz remains playable/editable without tagging; previous app versions remain functional before and after tagged quizzes exist.
5. Both Excel quiz-creation formats behave as before; upload still creates quizzes.
6. Sidecar writes and rule changes pass legacy-client/emulator compatibility tests and cannot rewrite existing quiz data.
7. Required CI jobs pass. A test not run is not a passing test.
8. Faculty/domain experts approve the pilot concepts and operational skill definitions. Suggestions are not treated as evidence.

## 9. Research protocol and integrity

- Define each of the small pilot skills with experts: meaning, observable evidence, suitable question types, and exclusions.
- Independently map a question subset with two experts where feasible; quantify disagreement and document adjudication rather than claiming agreement in advance.
- Pre-specify metrics and baselines before examining comparative results: overall quiz mark, naive tagged-topic performance, and the proposed interpretable evidence method.
- Report counts, distinct items, mapping provenance, scope, coverage, uncertainty method, confidence intervals where justified, and abstention.
- Evaluate robustness to reduced item counts and alternate valid mappings; use held-out expert-labelled or repeated comparable assessments where feasible.
- Obtain required institutional ethics/consent and privacy approvals. Exported questions, answers, code, and student data are restricted.
- A configurable minimum item count is a product safeguard, not psychometric validation. Scores are observations; competencies are estimates. Do not claim causal skill deficits or improved learning from this pilot.

## 10. Decisions to resolve before implementation

- Which course/unit and three-or-fewer candidate observable skills are approved for the pilot?
- Who is the taxonomy steward, and who may create, publish, retire, or merge shared concepts and skills?
- What do current RTDB security rules permit, and what additions are required without weakening existing protections?
- What is the exact previous-app compatibility window and how will its serializer/write behavior be tested?
- Which canonical fingerprint fields and conflict-resolution UX are appropriate for safely associating sidecar records with array-based legacy questions?
- What evidence minimum and report wording will be used for this pilot? The proposed five-item gate needs faculty/research approval.
- Which held-out/repeated assessment data and research permissions are available?

## 11. Repository source notes

These notes are limited to checked-in source inspection, not live Firebase or deployment verification:

- Quiz persistence and mirrored `questions` / `facultyQuestions`, plus whole-record `set` writes: [`faculty_quiz_manage.dart`](../frontend/lib/screens/faculty_quiz_manage.dart).
- MCQ edit reconstruction and richer coding/subjective handling: [`faculty_quiz_manage.dart`](../frontend/lib/screens/faculty_quiz_manage.dart).
- Quiz reads and question parsing: [`quiz_service.dart`](../frontend/lib/services/quiz_service.dart).
- Existing tests include Flutter widget coverage and backend unit tests under [`frontend/test`](../frontend/test) and [`backend`](../backend).
- Existing Vercel workflows deploy on path-filtered pushes; adding required pre-deploy test jobs is part of this plan: [frontend workflow](../.github/workflows/deploy_vercel.yml), [backend workflow](../.github/workflows/deploy_backend_vercel.yml).
