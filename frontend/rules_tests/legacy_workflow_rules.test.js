import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const projectId = 'demo-assessment-tagging';
const rules = readFileSync(
  new URL('./assessment_tagging.firestore.rules.test', import.meta.url),
  'utf8',
);
const firestorePort = Number(process.env.FIRESTORE_EMULATOR_PORT || 18080);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: firestorePort,
      rules,
    },
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

test('students can create their own quiz attempt with either supported UID field', async () => {
  const database = testEnvironment.authenticatedContext('student-one').firestore();

  await assertSucceeds(setDoc(doc(database, 'quiz_submissions', 'attempt-student-id'), {
    studentId: 'student-one',
    quizId: 'quiz-one',
    correctAnswers: 3,
    totalMarks: 4,
  }));
  await assertSucceeds(setDoc(doc(database, 'quiz_submissions', 'attempt-student-uid'), {
    studentUID: 'student-one',
    quizId: 'quiz-two',
  }));
});

test('quiz attempt creation rejects unauthenticated, other-user, and conflicting identities', async () => {
  const anonymousDatabase = testEnvironment.unauthenticatedContext().firestore();
  const studentDatabase = testEnvironment.authenticatedContext('student-one').firestore();

  await assertFails(setDoc(doc(anonymousDatabase, 'quiz_submissions', 'anonymous'), {
    studentId: 'student-one',
    quizId: 'quiz-one',
  }));
  await assertFails(setDoc(doc(studentDatabase, 'quiz_submissions', 'other-user'), {
    studentId: 'student-two',
    quizId: 'quiz-one',
  }));
  await assertFails(setDoc(doc(studentDatabase, 'quiz_submissions', 'conflicting-ids'), {
    studentId: 'student-one',
    studentUID: 'student-two',
    quizId: 'quiz-one',
  }));
});
