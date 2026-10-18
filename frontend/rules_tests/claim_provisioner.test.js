import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const script = fileURLToPath(new URL('./provision_assessment_claims.mjs', import.meta.url));

test('claim provisioner defaults to a dry run without credentials', () => {
  const result = spawnSync(
    process.execPath,
    [script, 'stela-staging', 'faculty_uid', 'faculty', 'course_one'],
    { encoding: 'utf8' },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /"assessmentFaculty": true/);
  assert.match(result.stdout, /"assessmentSubjectKey": "course_one"/);
  assert.match(result.stdout, /Dry run only/);
});

test('claim provisioner rejects missing project confirmation before Admin SDK use', () => {
  const result = spawnSync(
    process.execPath,
    [script, 'stela-staging', 'faculty_uid', 'faculty', 'course_one', '--apply'],
    { encoding: 'utf8' },
  );

  assert.equal(result.status, 2);
  assert.match(result.stderr, /exact --confirm-project match/);
});

test('claim provisioner does not accept a subject key for a non-faculty role', () => {
  const result = spawnSync(
    process.execPath,
    [script, 'stela-staging', 'student_uid', 'student', 'course_one'],
    { encoding: 'utf8' },
  );

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Usage:/);
});

test('claim provisioner can preview removal of managed access claims', () => {
  const result = spawnSync(
    process.execPath,
    [script, 'stela-staging', 'faculty_uid', 'student'],
    { encoding: 'utf8' },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /"claims": \{\}/);
  assert.match(result.stdout, /Dry run only/);
});

test('claim provisioner refuses the existing shared Firebase project', () => {
  const result = spawnSync(
    process.execPath,
    [script, 'stela23-f9a52', 'faculty_uid', 'faculty', 'course_one'],
    { encoding: 'utf8' },
  );

  assert.equal(result.status, 2);
  assert.match(result.stderr, /existing shared Firebase project/);
});
