import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, ref, set } from 'firebase/database';

const projectId = 'demo-assessment-tagging';
const rules = readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8');
const databasePort = Number(process.env.FIREBASE_DATABASE_EMULATOR_PORT || 9000);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    database: {
      host: '127.0.0.1',
      port: databasePort,
      rules,
    },
  });

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.database();
    await Promise.all([
      set(ref(database, 'question_tagging/course_one/quiz_one/reviewed'), {
        reviewed: true,
      }),
      set(ref(database, 'question_tagging/course_one/quiz_one/unreviewed'), {
        reviewed: false,
      }),
    ]);
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

test('anonymous users cannot read taxonomy or sidecars', async () => {
  const database = testEnvironment.unauthenticatedContext().database();

  await assertFails(get(ref(database, 'taxonomy/course_one')));
  await assertFails(get(ref(database, 'question_tagging/course_one')));
});

test('faculty claims grant writes only for their assigned subject key', async () => {
  const database = testEnvironment.authenticatedContext('faculty-one', {
    assessmentFaculty: true,
    assessmentSubjectKey: 'course_one',
  }).database();

  await assertSucceeds(set(ref(database, 'taxonomy/course_one/nodes/node-1'), {
    id: 'node-1',
    kind: 'concept',
  }));
  await assertSucceeds(set(ref(database, 'question_tagging/course_one/quiz_one/new'), {
    reviewed: false,
  }));
  await assertSucceeds(get(ref(database, 'question_tagging/course_one/quiz_one/unreviewed')));

  await assertFails(set(ref(database, 'taxonomy/course_two/nodes/node-1'), {
    id: 'node-1',
    kind: 'concept',
  }));
  await assertFails(set(ref(database, 'question_tagging/course_two/quiz_one/new'), {
    reviewed: false,
  }));
});

test('missing or incomplete faculty claims fail closed', async () => {
  const noClaimsDatabase = testEnvironment.authenticatedContext('no-claims').database();
  const noCourseDatabase = testEnvironment.authenticatedContext('no-course', {
    assessmentFaculty: true,
  }).database();

  await assertFails(set(ref(noClaimsDatabase, 'taxonomy/course_one/nodes/denied'), {
    id: 'denied',
  }));
  await assertFails(set(ref(noClaimsDatabase, 'question_tagging/course_one/quiz_one/denied'), {
    reviewed: true,
  }));
  await assertFails(set(ref(noCourseDatabase, 'taxonomy/course_one/nodes/denied'), {
    id: 'denied',
  }));
  await assertFails(set(ref(noCourseDatabase, 'question_tagging/course_one/quiz_one/denied'), {
    reviewed: true,
  }));
});

test('admin and taxonomy steward claims grant cross-course writes', async () => {
  const adminDatabase = testEnvironment.authenticatedContext('admin', {
    assessmentAdmin: true,
  }).database();
  const stewardDatabase = testEnvironment.authenticatedContext('steward', {
    taxonomySteward: true,
  }).database();

  await assertSucceeds(set(ref(adminDatabase, 'taxonomy/course_two/nodes/admin-node'), {
    id: 'admin-node',
  }));
  await assertSucceeds(set(ref(stewardDatabase, 'question_tagging/course_two/quiz_two/q1'), {
    reviewed: true,
  }));
});

test('students read reviewed and missing sidecars but not unreviewed data', async () => {
  const database = testEnvironment.authenticatedContext('student').database();

  await assertSucceeds(get(ref(database, 'taxonomy/course_one')));
  await assertSucceeds(get(ref(database, 'question_tagging/course_one/quiz_one/reviewed')));
  await assertSucceeds(get(ref(database, 'question_tagging/course_one/quiz_one/missing')));
  await assertFails(get(ref(database, 'question_tagging/course_one/quiz_one/unreviewed')));
  await assertFails(set(ref(database, 'question_tagging/course_one/quiz_one/reviewed'), {
    reviewed: false,
  }));
  await assertFails(set(ref(database, 'taxonomy/course_one/nodes/student-node'), {
    id: 'student-node',
  }));
});

test('student evidence remains private to its owner', async () => {
  const ownerDatabase = testEnvironment.authenticatedContext('student-one').database();
  const otherDatabase = testEnvironment.authenticatedContext('student-two').database();

  await assertSucceeds(set(ref(ownerDatabase, 'student_evidence/student-one/quiz-one'), {
    score: 0.8,
  }));
  await assertSucceeds(get(ref(ownerDatabase, 'student_evidence/student-one/quiz-one')));
  await assertFails(get(ref(otherDatabase, 'student_evidence/student-one/quiz-one')));
  await assertFails(set(ref(otherDatabase, 'student_evidence/student-one/quiz-one'), {
    score: 0,
  }));
});

test('database clients cannot create or change their own authorization claims', async () => {
  const database = testEnvironment.authenticatedContext('self-promoting-user').database();

  await assertFails(set(ref(database, 'user_roles/self-promoting-user'), {
    role: 'admin',
  }));
});
