import hashlib
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path
from typing import Any
from unittest.mock import patch

from rtdb_migrate import (
    _confirm_backup_review,
    _confirm_destination,
    _ensure_outside_repository,
    MigrationError,
    RealtimeDatabaseClient,
    copy_database,
    validate_database_url,
)


class FakeResponse:
    def __init__(self, value: Any, etag: str = '"etag-1"', status: int = 200) -> None:
        self.status = status
        self.headers = {"ETag": etag}
        self._body = (
            value if isinstance(value, bytes) else json.dumps(value).encode("utf-8")
        )

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: Any) -> None:
        return False if _args else None

    def read(self, size: int = -1) -> bytes:
        return self._body[:size] if size >= 0 else self._body


class QueueOpener:
    def __init__(self, responses: list[Any]) -> None:
        self.responses = responses
        self.requests = []

    def __call__(self, request: Any, timeout: int) -> FakeResponse:
        if timeout != 120:
            raise AssertionError("HTTP requests must use the configured timeout.")
        self.requests.append(request)
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def accept_backup_review(backup_path: Path, digest: str) -> None:
    if not backup_path.is_file() or len(digest) != 64:
        raise AssertionError("Backup review requires a written backup and SHA-256.")


class ValidateDatabaseUrlTests(unittest.TestCase):
    def test_accepts_firebase_database_hosts(self) -> None:
        self.assertEqual(
            validate_database_url(
                "https://sample-default-rtdb.asia-southeast1.firebasedatabase.app/"
            ),
            "https://sample-default-rtdb.asia-southeast1.firebasedatabase.app",
        )

    def test_rejects_non_https_and_paths(self) -> None:
        for url in (
            "http://sample-default-rtdb.firebaseio.com",
            "https://example.com",
            "https://sample-default-rtdb.firebaseio.com/private",
            "https://user:password@sample-default-rtdb.firebaseio.com",
        ):
            with self.subTest(url=url), self.assertRaises(MigrationError):
                validate_database_url(url)


class ConfirmDestinationTests(unittest.TestCase):
    def test_confirmation_requires_exact_destination_hostname(self) -> None:
        with patch("builtins.input", return_value="expected.firebaseio.com"):
            _confirm_destination("expected.firebaseio.com")

    def test_wrong_confirmation_aborts(self) -> None:
        with patch("builtins.input", return_value="other.firebaseio.com"):
            with self.assertRaisesRegex(MigrationError, "did not match"):
                _confirm_destination("expected.firebaseio.com")


class ConfirmBackupReviewTests(unittest.TestCase):
    def test_confirmation_requires_exact_snapshot_hash(self) -> None:
        with patch("builtins.input", return_value="COPY abc123"):
            _confirm_backup_review(Path("backup.json"), "abc123")

    def test_wrong_hash_aborts(self) -> None:
        with patch("builtins.input", return_value="COPY wrong"):
            with self.assertRaisesRegex(MigrationError, "No destination write occurred"):
                _confirm_backup_review(Path("backup.json"), "abc123")


class RealtimeDatabaseClientTests(unittest.TestCase):
    def test_get_root_requests_etag_and_parses_database_value(self) -> None:
        opener = QueueOpener([FakeResponse({"quizzes": {"q1": {"title": "Quiz"}}})])
        client = RealtimeDatabaseClient(
            "https://sample-default-rtdb.firebaseio.com",
            "not-printed-token",
            opener,
        )

        snapshot = client.get_root()

        self.assertEqual(snapshot.value, {"quizzes": {"q1": {"title": "Quiz"}}})
        self.assertEqual(snapshot.etag, '"etag-1"')
        self.assertEqual(opener.requests[0].get_header("X-firebase-etag"), "true")
        self.assertIn("format=export", opener.requests[0].full_url)
        self.assertNotIn("not-printed-token", opener.requests[0].full_url)

    def test_put_uses_etag_precondition(self) -> None:
        opener = QueueOpener([FakeResponse(None)])
        client = RealtimeDatabaseClient(
            "https://sample-default-rtdb.firebaseio.com",
            "token",
            opener,
        )

        client.put_root_if_unchanged({"key": "value"}, '"etag-2"')

        request = opener.requests[0]
        self.assertEqual(request.get_method(), "PUT")
        self.assertEqual(request.get_header("If-match"), '"etag-2"')

    def test_put_stops_when_destination_changed(self) -> None:
        opener = QueueOpener(
            [
                urllib.error.HTTPError(
                    "https://sample-default-rtdb.firebaseio.com/.json",
                    412,
                    "Precondition Failed",
                    {},
                    None,
                )
            ]
        )
        client = RealtimeDatabaseClient(
            "https://sample-default-rtdb.firebaseio.com",
            "token",
            opener,
        )

        with self.assertRaisesRegex(MigrationError, "No data was overwritten"):
            client.put_root_if_unchanged({"key": "value"}, '"old-etag"')


class CopyDatabaseTests(unittest.TestCase):
    def test_copy_rejects_same_source_and_destination_without_network_access(self) -> None:
        opener = QueueOpener([])
        source = RealtimeDatabaseClient(
            "https://same-default-rtdb.firebaseio.com",
            "token",
            opener,
        )
        destination = RealtimeDatabaseClient(
            "https://same-default-rtdb.firebaseio.com/",
            "token",
            opener,
        )

        with self.assertRaisesRegex(MigrationError, "must differ"):
            copy_database(
                source,
                destination,
                backup_directory=Path("unused-backup"),
                repository_root=Path("repo"),
                confirm_backup_review=accept_backup_review,
            )
        self.assertEqual(opener.requests, [])

    def test_copy_refuses_non_empty_destination_before_backup_or_write(self) -> None:
        source = RealtimeDatabaseClient(
            "https://source-default-rtdb.firebaseio.com",
            "token",
            QueueOpener([FakeResponse({"users": {"u1": {"name": "private"}}})]),
        )
        destination_opener = QueueOpener([FakeResponse({"existing": "data"})])
        destination = RealtimeDatabaseClient(
            "https://destination-default-rtdb.firebaseio.com",
            "token",
            destination_opener,
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backup_directory = root / "backups"
            repository_root = root / "repo"
            repository_root.mkdir()

            with self.assertRaisesRegex(MigrationError, "Destination database is not empty"):
                copy_database(
                    source,
                    destination,
                    backup_directory=backup_directory,
                    repository_root=repository_root,
                    confirm_backup_review=accept_backup_review,
                )

            self.assertFalse(backup_directory.exists())
            self.assertEqual(len(destination_opener.requests), 1)

    def test_copy_backups_then_conditionally_writes_and_verifies(self) -> None:
        source_data = {
            "quizzes": {"quiz1": {"title": "Pilot"}},
            "orderedRecords": {"2": "second", "1": "first", ".priority": 3},
        }
        source = RealtimeDatabaseClient(
            "https://source-default-rtdb.firebaseio.com",
            "token",
            QueueOpener([FakeResponse(source_data)]),
        )
        destination_opener = QueueOpener(
            [
                FakeResponse(None, '"empty-etag"'),
                FakeResponse(None, '"empty-etag"'),
                FakeResponse(None),
                FakeResponse(source_data, '"copied-etag"'),
            ]
        )
        destination = RealtimeDatabaseClient(
            "https://destination-default-rtdb.firebaseio.com",
            "token",
            destination_opener,
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repository_root = root / "repo"
            repository_root.mkdir()
            backup_directory = root / "private-backups"

            backup_path, manifest_path = copy_database(
                source,
                destination,
                backup_directory=backup_directory,
                repository_root=repository_root,
                confirm_backup_review=accept_backup_review,
            )

            self.assertEqual(json.loads(backup_path.read_text()), source_data)
            manifest = json.loads(manifest_path.read_text())
            self.assertEqual(manifest["sourceDatabaseHost"], "source-default-rtdb.firebaseio.com")
            self.assertTrue(manifest["sha256"])
            self.assertEqual(
                [request.get_method() for request in destination_opener.requests],
                ["GET", "GET", "PUT", "GET"],
            )

    def test_declined_backup_review_preserves_backup_without_writing(self) -> None:
        source = RealtimeDatabaseClient(
            "https://source-default-rtdb.firebaseio.com",
            "token",
            QueueOpener([FakeResponse({"quizzes": {"q1": {"title": "Quiz"}}})]),
        )
        destination_opener = QueueOpener([FakeResponse(None, '"empty-etag"')])
        destination = RealtimeDatabaseClient(
            "https://destination-default-rtdb.firebaseio.com",
            "token",
            destination_opener,
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repository_root = root / "repo"
            repository_root.mkdir()
            backup_directory = root / "backups"

            def decline_review(path: Path, digest: str) -> None:
                self.assertTrue(path.is_file())
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
                raise MigrationError("Backup review declined.")

            with self.assertRaisesRegex(MigrationError, "declined"):
                copy_database(
                    source,
                    destination,
                    backup_directory=backup_directory,
                    repository_root=repository_root,
                    confirm_backup_review=decline_review,
                )

            backups = [
                candidate / "realtime-database.json"
                for candidate in backup_directory.glob("rtdb-backup-*")
                if candidate.is_dir()
            ]
            self.assertEqual(len(backups), 1)
            self.assertTrue(backups[0].is_file())
            self.assertEqual(len(destination_opener.requests), 1)

    def test_backup_directory_inside_repository_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repository = root / "repo"
            repository.mkdir()

            with self.assertRaisesRegex(MigrationError, "outside the repository"):
                _ensure_outside_repository(repository / "backup", repository)


if __name__ == "__main__":
    unittest.main()
