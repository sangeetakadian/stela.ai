const args = process.argv.slice(2);
const options = new Set(args.filter((argument) => argument.startsWith('--')));
const positional = args.filter((argument) => !argument.startsWith('--'));
const [projectId, uid, role, subjectKey] = positional;
const allowedRoles = new Set(['student', 'faculty', 'admin', 'taxonomy-steward']);
const sharedProjectId = 'stela23-f9a52';
const managedClaims = [
  'assessmentFaculty',
  'assessmentSubjectKey',
  'assessmentAdmin',
  'taxonomySteward',
];

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

if (
  !projectId ||
  !uid ||
  !allowedRoles.has(role) ||
  (role === 'faculty' && (!subjectKey || positional.length !== 4)) ||
  (role !== 'faculty' && positional.length !== 3) ||
  [...options].some((option) => !['--apply', `--confirm-project=${projectId}`].some(
    (expected) => option === expected,
  ))
) {
  console.error(
    'Usage: node provision_assessment_claims.mjs <project-id> <uid> <student|faculty|admin|taxonomy-steward> [subject-key] [--apply] [--confirm-project=<project-id>]',
  );
  process.exit(2);
}

if (projectId === sharedProjectId) {
  console.error('Refusing to provision claims on the existing shared Firebase project.');
  process.exit(2);
}

if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
  fail('UID must contain only letters, digits, underscores, or hyphens.');
  process.exit(2);
}

if (role === 'faculty' && !/^[A-Za-z0-9_-]{1,128}$/.test(subjectKey)) {
  fail('Faculty subject key must contain only letters, digits, underscores, or hyphens.');
  process.exit(2);
}

const claims = {};
if (role === 'faculty') {
  claims.assessmentFaculty = true;
  claims.assessmentSubjectKey = subjectKey;
} else if (role === 'admin') {
  claims.assessmentAdmin = true;
} else if (role === 'taxonomy-steward') {
  claims.taxonomySteward = true;
}

if (!options.has('--apply')) {
  console.log(JSON.stringify({ projectId, uid, role, claims, apply: false }, null, 2));
  console.log('Dry run only. Add --apply and --confirm-project=<project-id> to proceed.');
  process.exit(0);
}

if (!options.has(`--confirm-project=${projectId}`)) {
  fail('Applying claims requires an exact --confirm-project match.');
  process.exit(2);
}

try {
  const [{ initializeApp }, { getAuth }] = await Promise.all([
    import('firebase-admin/app'),
    import('firebase-admin/auth'),
  ]);
  const app = initializeApp({ projectId }, `assessment-claims-${projectId}`);
  const auth = getAuth(app);
  const user = await auth.getUser(uid);
  const nextClaims = { ...(user.customClaims ?? {}) };
  for (const claim of managedClaims) {
    delete nextClaims[claim];
  }
  Object.assign(nextClaims, claims);
  await auth.setCustomUserClaims(uid, nextClaims);
  console.log(`Updated assessment claims for UID ${uid} in project ${projectId} as ${role}.`);
  console.log('The user must refresh their Firebase ID token before the new claims take effect.');
} catch (error) {
  console.error(`Failed to provision assessment claims: ${error.message}`);
  process.exitCode = 1;
}
