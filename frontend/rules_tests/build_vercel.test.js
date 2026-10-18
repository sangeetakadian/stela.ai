import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const buildScript = fileURLToPath(
  new URL('../scripts/build_vercel.sh', import.meta.url),
);

function runBuild(env) {
  const tempDirectory = mkdtempSync(
    path.join(os.tmpdir(), 'istela-vercel-build-test-'),
  );
  const flutterStub = path.join(tempDirectory, 'flutter');
  writeFileSync(
    flutterStub,
    '#!/usr/bin/env bash\nprintf "FLUTTER_ARGS=%s\\\\n" "$*"\n',
  );
  chmodSync(flutterStub, 0o755);

  try {
    return spawnSync('bash', [buildScript], {
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDirectory}${path.delimiter}${process.env.PATH ?? ''}`,
        ...env,
      },
    });
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
}

const validPilotEnvironment = {
  VERCEL_ENV: 'preview',
  ISTELA_ASSESSMENT_PILOT_BUILD: 'true',
  CODE_EXEC_ENDPOINT: 'https://pilot.example/execute',
  PILOT_FIREBASE_API_KEY: 'pilot-api-key',
  PILOT_FIREBASE_APP_ID: '1:123:web:pilot',
  PILOT_FIREBASE_MESSAGING_SENDER_ID: '123',
  PILOT_FIREBASE_PROJECT_ID: 'assessment-pilot-test',
  PILOT_FIREBASE_DATABASE_URL:
    'https://assessment-pilot-test-default-rtdb.firebaseio.com',
  PILOT_FIREBASE_AUTH_DOMAIN: 'assessment-pilot-test.firebaseapp.com',
  PILOT_FIREBASE_STORAGE_BUCKET: 'assessment-pilot-test.firebasestorage.app',
};

test('Preview build forwards pilot Firebase configuration', () => {
  const result = runBuild(validPilotEnvironment);

  assert.equal(result.status, 0, result.stderr);
  assert.match(
    result.stdout,
    /--dart-define=PILOT_FIREBASE_PROJECT_ID=assessment-pilot-test/,
  );
  assert.match(result.stdout, /--dart-define=ISTELA_ASSESSMENT_PILOT=true/);
});

test('Preview build rejects incomplete pilot Firebase configuration', () => {
  const { PILOT_FIREBASE_PROJECT_ID: _, ...incompleteEnvironment } =
    validPilotEnvironment;
  const result = runBuild(incompleteEnvironment);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing Preview environment variable/);
});

test('Preview build refuses the existing shared Firebase project', () => {
  const result = runBuild({
    ...validPilotEnvironment,
    PILOT_FIREBASE_PROJECT_ID: 'stela23-f9a52',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /existing shared Firebase project/);
});

test('non-Preview build does not pass pilot Firebase configuration', () => {
  const result = runBuild({
    VERCEL_ENV: 'production',
    CODE_EXEC_ENDPOINT: 'https://existing.example/execute',
    PILOT_FIREBASE_PROJECT_ID: 'stela23-f9a52',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /--dart-define=CODE_EXEC_ENDPOINT=/);
  assert.doesNotMatch(result.stdout, /PILOT_FIREBASE_PROJECT_ID/);
});

test('ordinary Vercel Preview builds do not require pilot configuration', () => {
  const result = runBuild({
    VERCEL_ENV: 'preview',
    CODE_EXEC_ENDPOINT: 'https://existing-preview.example/execute',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /--dart-define=CODE_EXEC_ENDPOINT=/);
  assert.doesNotMatch(result.stdout, /PILOT_FIREBASE_PROJECT_ID/);
});

test('pilot configuration cannot be used in a production build', () => {
  const result = runBuild({
    ...validPilotEnvironment,
    VERCEL_ENV: 'production',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /only allowed in the Vercel Preview environment/);
});
