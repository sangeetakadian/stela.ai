"""Safely back up or copy a complete Firebase Realtime Database instance."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


MAX_TRANSFER_BYTES = 200 * 1024 * 1024
DATABASE_SCOPES = ("https://www.googleapis.com/auth/cloud-platform",)
ALLOWED_DATABASE_SUFFIXES = (
    ".firebasedatabase.app",
    ".firebaseio.com",
)


class MigrationError(RuntimeError):
    """A validation, authentication, or database transfer failed safely."""


@dataclass(frozen=True)
class DatabaseSnapshot:
    value: Any
    etag: str
    size_bytes: int


def validate_database_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    hostname = (parsed.hostname or "").lower()
    if (
        parsed.scheme != "https"
        or not hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
        or not any(hostname.endswith(suffix) for suffix in ALLOWED_DATABASE_SUFFIXES)
    ):
        raise MigrationError(
            "Database URL must be an HTTPS Firebase Realtime Database instance URL."
        )
    return f"https://{hostname}"


def _serialize(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise MigrationError("Database response could not be serialized as JSON.") from exc


class RealtimeDatabaseClient:
    def __init__(
        self,
        database_url: str,
        access_token: str,
        opener: Callable[..., Any] = urllib.request.urlopen,
    ) -> None:
        self.database_url = validate_database_url(database_url)
        self._access_token = access_token
        self._opener = opener

    def get_root(self) -> DatabaseSnapshot:
        request = urllib.request.Request(
            f"{self.database_url}/.json?format=export",
            headers={
                "Authorization": f"Bearer {self._access_token}",
                "X-Firebase-ETag": "true",
            },
            method="GET",
        )
        response = self._send(request)
        etag = response.headers.get("ETag")
        if not etag:
            raise MigrationError(
                "Realtime Database did not return an ETag; refusing an unsafe copy."
            )
        try:
            value = json.loads(response.body)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise MigrationError("Realtime Database returned invalid JSON.") from exc
        return DatabaseSnapshot(value, etag, len(response.body))

    def put_root_if_unchanged(self, value: Any, etag: str) -> None:
        body = _serialize(value)
        if len(body) > MAX_TRANSFER_BYTES:
            raise MigrationError(
                "The database export exceeds the script's 200 MiB safe transfer limit."
            )
        request = urllib.request.Request(
            f"{self.database_url}/.json?format=export",
            data=body,
            headers={
                "Authorization": f"Bearer {self._access_token}",
                "Content-Type": "application/json; charset=utf-8",
                "If-Match": etag,
            },
            method="PUT",
        )
        response = self._send(request, allow_precondition_failure=True)
        if response.status == 412:
            raise MigrationError(
                "Destination changed after it was checked. No data was overwritten."
            )

    def _send(
        self,
        request: urllib.request.Request,
        *,
        allow_precondition_failure: bool = False,
    ) -> "_HttpResponse":
        try:
            with self._opener(request, timeout=120) as response:
                body = response.read(MAX_TRANSFER_BYTES + 1)
                if len(body) > MAX_TRANSFER_BYTES:
                    raise MigrationError(
                        "The database response exceeds the script's 200 MiB safe transfer limit."
                    )
                return _HttpResponse(response.status, response.headers, body)
        except urllib.error.HTTPError as exc:
            if allow_precondition_failure and exc.code == 412:
                return _HttpResponse(exc.code, exc.headers, b"")
            if exc.code in (401, 403):
                raise MigrationError(
                    f"Firebase access was denied (HTTP {exc.code}); verify the signed-in identity and database permissions."
                ) from None
            raise MigrationError(
                f"Realtime Database request failed (HTTP {exc.code})."
            ) from None
        except urllib.error.URLError as exc:
            raise MigrationError(
                f"Could not reach Realtime Database: {exc.reason}"
            ) from None


@dataclass(frozen=True)
class _HttpResponse:
    status: int
    headers: Any
    body: bytes


def load_access_token(credentials_file: Path | None) -> str:
    try:
        import google.auth
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError as exc:
        raise MigrationError(
            "Install the migration dependencies with "
            "'python -m pip install -r tools/requirements-rtdb-migration.txt'."
        ) from exc

    try:
        if credentials_file is not None:
            credentials = service_account.Credentials.from_service_account_file(
                str(credentials_file),
                scopes=DATABASE_SCOPES,
            )
        else:
            credentials, _ = google.auth.default(scopes=DATABASE_SCOPES)
        credentials.refresh(Request())
    except Exception as exc:
        raise MigrationError(
            "Google authentication failed. Configure Application Default "
            "Credentials or pass a local service-account file with access to "
            "both databases. Do not paste credentials into chat or commit them."
        ) from exc

    if not credentials.token:
        raise MigrationError("Google authentication returned no access token.")
    return credentials.token


def _secure_directory(path: Path) -> None:
    try:
        path.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise MigrationError(
            "Backup run directory already exists; refusing to reuse it."
        ) from exc
    if os.name == "nt":
        identity = subprocess.run(
            ["whoami"], check=True, capture_output=True, text=True
        ).stdout.strip()
        result = subprocess.run(
            [
                "icacls",
                str(path),
                "/inheritance:r",
                "/grant:r",
                f"{identity}:(OI)(CI)F",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise MigrationError(
                "Could not restrict backup directory access with Windows ACLs."
            )
    else:
        path.chmod(0o700)


def _secure_file(path: Path) -> None:
    if os.name == "nt":
        identity = subprocess.run(
            ["whoami"], check=True, capture_output=True, text=True
        ).stdout.strip()
        result = subprocess.run(
            [
                "icacls",
                str(path),
                "/inheritance:r",
                "/grant:r",
                f"{identity}:F",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            path.unlink(missing_ok=True)
            raise MigrationError("Could not restrict backup file access with Windows ACLs.")
    else:
        path.chmod(0o600)


def _ensure_outside_repository(path: Path, repository_root: Path) -> None:
    resolved_path = path.resolve()
    resolved_root = repository_root.resolve()
    if resolved_path == resolved_root or resolved_root in resolved_path.parents:
        raise MigrationError("Backup directory must be outside the repository.")


def write_backup(
    snapshot: DatabaseSnapshot,
    *,
    backup_directory: Path,
    repository_root: Path,
    source_url: str,
) -> tuple[Path, Path, str]:
    payload = _serialize(snapshot.value)
    if len(payload) > MAX_TRANSFER_BYTES:
        raise MigrationError(
            "The database export exceeds the script's 200 MiB safe transfer limit."
        )

    digest = hashlib.sha256(payload).hexdigest()
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    export_directory = backup_directory / f"rtdb-backup-{timestamp}"
    _ensure_outside_repository(export_directory, repository_root)
    _secure_directory(export_directory)
    backup_path = export_directory / "realtime-database.json"
    manifest_path = export_directory / "realtime-database.manifest.json"

    if backup_path.exists() or manifest_path.exists():
        raise MigrationError("A backup already exists for this run; retry shortly.")

    temporary_path = backup_path.with_suffix(".json.tmp")
    try:
        temporary_path.write_bytes(payload)
        _secure_file(temporary_path)
        os.replace(temporary_path, backup_path)
        manifest = {
            "createdAtUtc": datetime.now(timezone.utc).isoformat(),
            "sourceDatabaseHost": urllib.parse.urlsplit(source_url).hostname,
            "sha256": digest,
            "sizeBytes": len(payload),
            "etag": snapshot.etag,
        }
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
        )
        _secure_file(manifest_path)
    except OSError as exc:
        temporary_path.unlink(missing_ok=True)
        backup_path.unlink(missing_ok=True)
        manifest_path.unlink(missing_ok=True)
        raise MigrationError(f"Could not write the private backup: {exc}") from exc

    return backup_path, manifest_path, digest


def copy_database(
    source: RealtimeDatabaseClient,
    destination: RealtimeDatabaseClient,
    *,
    backup_directory: Path,
    repository_root: Path,
    confirm_backup_review: Callable[[Path, str], None],
) -> tuple[Path, Path]:
    if source.database_url == destination.database_url:
        raise MigrationError("Source and destination database URLs must differ.")

    source_snapshot = source.get_root()
    if source_snapshot.value is None:
        raise MigrationError("Source database is empty; refusing to copy.")

    source_digest = hashlib.sha256(_serialize(source_snapshot.value)).hexdigest()
    destination_snapshot = destination.get_root()
    if destination_snapshot.value is not None:
        raise MigrationError(
            "Destination database is not empty. No destination data was changed."
        )

    backup_path, manifest_path, _ = write_backup(
        source_snapshot,
        backup_directory=backup_directory,
        repository_root=repository_root,
        source_url=source.database_url,
    )
    confirm_backup_review(backup_path, source_digest)

    # Re-read to obtain a fresh ETag; the conditional PUT prevents a race from
    # overwriting writes made after the empty-destination check.
    destination_snapshot = destination.get_root()
    if destination_snapshot.value is not None:
        raise MigrationError(
            f"Destination became non-empty after backup. No data was overwritten. Backup: {backup_path}"
        )
    destination.put_root_if_unchanged(
        source_snapshot.value,
        destination_snapshot.etag,
    )

    copied_snapshot = destination.get_root()
    copied_digest = hashlib.sha256(_serialize(copied_snapshot.value)).hexdigest()
    if copied_digest != source_digest:
        raise MigrationError(
            f"Destination verification failed. Preserve the source and backup at {backup_path}; do not retry blindly."
        )
    return backup_path, manifest_path


def _default_backup_directory() -> Path:
    home = Path.home()
    return home / "stela-private-backups"


def _confirm_destination(hostname: str) -> None:
    print(
        "This operation can write the complete source database to the empty "
        "destination. The script will not merge or delete destination data."
    )
    try:
        confirmation = input(f"Type the exact destination hostname ({hostname}) to continue: ")
    except EOFError as exc:
        raise MigrationError(
            "Interactive destination confirmation is required."
        ) from exc
    if confirmation.strip().lower() != hostname.lower():
        raise MigrationError("Destination confirmation did not match; no copy started.")


def _confirm_backup_review(backup_path: Path, digest: str) -> None:
    print(f"Source backup: {backup_path}")
    print(f"Backup SHA-256: {digest}")
    try:
        confirmation = input(
            "Inspect the backup and manifest. Type "
            f"'COPY {digest}' to authorize writing this exact snapshot: "
        )
    except EOFError as exc:
        raise MigrationError(
            f"Backup review confirmation is required. Backup preserved at {backup_path}"
        ) from exc
    if confirmation.strip() != f"COPY {digest}":
        raise MigrationError(
            f"Backup review confirmation did not match. No destination write occurred; backup preserved at {backup_path}"
        )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Back up or safely copy a Firebase Realtime Database. "
            "A copy requires an empty destination and an explicit confirmation flag."
        )
    )
    subparsers = parser.add_subparsers(dest="operation", required=True)

    backup_parser = subparsers.add_parser("backup", help="Create a private full RTDB backup.")
    backup_parser.add_argument("--source-url", required=True)
    backup_parser.add_argument(
        "--backup-directory",
        type=Path,
        default=_default_backup_directory(),
    )
    backup_parser.add_argument("--credentials-file", type=Path)

    copy_parser = subparsers.add_parser(
        "copy",
        help="Back up the source, then copy it only into an empty destination.",
    )
    copy_parser.add_argument("--source-url", required=True)
    copy_parser.add_argument("--destination-url", required=True)
    copy_parser.add_argument(
        "--backup-directory",
        type=Path,
        default=_default_backup_directory(),
    )
    copy_parser.add_argument("--credentials-file", type=Path)
    copy_parser.add_argument(
        "--confirm-copy",
        action="store_true",
        help="Explicitly authorize writing the source snapshot to the empty destination.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if args.operation == "copy" and not args.confirm_copy:
        raise MigrationError(
            "Copy not started. Review the source/destination URLs, then rerun with --confirm-copy."
        )

    source_url = validate_database_url(args.source_url)
    destination_url = (
        validate_database_url(args.destination_url)
        if args.operation == "copy"
        else None
    )
    if destination_url is not None:
        destination_hostname = urllib.parse.urlsplit(destination_url).hostname
        if destination_hostname is None:
            raise MigrationError("Could not determine the destination hostname.")
        _confirm_destination(destination_hostname)
    repository_root = Path(__file__).resolve().parents[1]
    if args.credentials_file is not None:
        _ensure_outside_repository(args.credentials_file, repository_root)
        if not args.credentials_file.is_file():
            raise MigrationError("The credentials file does not exist.")
    token = load_access_token(args.credentials_file)
    source = RealtimeDatabaseClient(source_url, token)

    if args.operation == "backup":
        snapshot = source.get_root()
        backup_path, manifest_path, digest = write_backup(
            snapshot,
            backup_directory=args.backup_directory,
            repository_root=repository_root,
            source_url=source_url,
        )
        print(f"Backup written: {backup_path}")
        print(f"Manifest written: {manifest_path}")
        print(f"SHA-256: {digest}")
        return 0

    if destination_url is None:
        raise MigrationError("Copy operation requires a destination database URL.")
    destination = RealtimeDatabaseClient(destination_url, token)
    backup_path, manifest_path = copy_database(
        source,
        destination,
        backup_directory=args.backup_directory,
        repository_root=repository_root,
        confirm_backup_review=_confirm_backup_review,
    )
    print("Realtime Database copy and read-back verification succeeded.")
    print(f"Source backup: {backup_path}")
    print(f"Backup manifest: {manifest_path}")
    print(f"Destination: {destination.database_url}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MigrationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
