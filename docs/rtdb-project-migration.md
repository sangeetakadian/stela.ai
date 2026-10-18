# Realtime Database project backup and copy

This is a separate infrastructure operation from the question-tagging feature.
It copies the complete source Realtime Database to the destination project;
it is not a merge and does not copy Firestore, Firebase Storage, Auth users,
Hosting configuration, security rules, indexes, or other Firebase services.

**Never run a production copy until you have inspected the backup, verified
the destination project, and confirmed that its Realtime Database is empty.**
The script intentionally refuses a non-empty destination and never deletes
destination data.

## Current project endpoints

- Source: `stela23-f9a52` Realtime Database.
- Destination: `ailearn-e767a` Realtime Database in the supplied
  `asia-southeast1` instance.

The Firebase web `apiKey` in app configuration identifies the app; it is not
authorization for an administrative database export or import. No access
tokens, private keys, or credentials belong in this repository or in chat.

## Authorization prerequisites

The migration script uses Google Application Default Credentials (ADC), or an
explicit service-account file supplied locally. The authenticated principal
must be authorized to read the entire source database and write the destination
database. Prefer user ADC and narrowly scoped project access over long-lived
service-account keys.

The current development environment did not have Firebase CLI, Google Cloud
CLI, or Google ADC configured when this script was prepared. Therefore no live
database read, backup, or write has been performed. If using ADC, install the
Google Cloud CLI and authenticate locally with:

```powershell
gcloud auth application-default login
```

Install the Python dependency from the repository root:

```powershell
python -m pip install -r tools\requirements-rtdb-migration.txt
```

## 1. Create and inspect a private source backup

Run from the repository root. The default output is outside the repository at
`%USERPROFILE%\stela-private-backups`, in a per-run directory whose Windows
ACL is restricted to the current user. The script also refuses an explicitly
chosen backup path inside the repository.

```powershell
python tools\rtdb_migrate.py backup `
  --source-url "https://stela23-f9a52-default-rtdb.asia-southeast1.firebasedatabase.app/"
```

The export uses Firebase's `format=export` representation, includes RTDB
priority metadata, writes a SHA-256 manifest, and aborts above 200 MiB. Store
the backup securely: it may include private student data, quiz answers, and
other sensitive records. The script restricts the backup directory/file ACL to
the current Windows user but does **not encrypt** the JSON at rest. Use a
BitLocker-protected or otherwise encrypted disk, do not sync/share the backup,
and inspect the generated manifest and backup using an approved secure process
before proceeding.

If an authorized local service-account file is required instead of ADC, pass
its path with `--credentials-file "C:\secure\path\service-account.json"`.
The script refuses a credentials file inside the repository. Never commit or
share the service-account file.

## 2. Copy to the empty destination

First verify in Firebase Console that the selected destination instance is the
intended project and is empty. The script checks this itself as well. Only
after reviewing the backup and accepting a full database copy, run:

```powershell
python tools\rtdb_migrate.py copy `
  --source-url "https://stela23-f9a52-default-rtdb.asia-southeast1.firebasedatabase.app/" `
  --destination-url "https://ailearn-e767a-default-rtdb.asia-southeast1.firebasedatabase.app/" `
  --confirm-copy
```

The explicit `--confirm-copy` flag is required. Before writing, the script:

1. Prompts you to type the exact destination hostname.
2. Reads and snapshots the source.
3. Confirms the destination is empty.
4. Writes a private source backup.
5. Pauses so you can inspect the backup and manifest; requires typing
   `COPY <exact SHA-256>` to authorize this snapshot.
6. Re-reads the destination to get a fresh ETag.
7. Uses an ETag-conditional root write so a concurrent destination change
   causes an abort instead of being overwritten.
8. Reads the destination back and verifies its exported JSON hash.

The root write is not a merge. The operation aborts on a non-empty destination,
source/destination URL equality, missing ETags, access errors, oversized data,
or a verification mismatch. It does not copy security rules; review and
configure destination rules separately before exposing the new project to the
app. Do not use this utility as a restore/overwrite tool.

## Offline safety tests

The script has 14 mocked HTTP tests only; they do not access Firebase:

```powershell
python -m unittest discover -s tools -p "test_rtdb_migrate.py" -v
```

Do not test copy/restore behavior against a production database. Use separate
Firebase Emulator instances or disposable projects for end-to-end validation.
