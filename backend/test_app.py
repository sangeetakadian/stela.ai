import unittest
from unittest.mock import patch

import app as backend_app
from sandbox_runner import ExecutionResult


class ExecuteRouteTests(unittest.TestCase):
    def setUp(self):
        backend_app.app.config.update(TESTING=True)
        backend_app._rate_limit_buckets.clear()
        self.client = backend_app.app.test_client()

    def test_execute_preflight_allows_local_development_origins(self):
        origin = "http://localhost:54321"
        response = self.client.options(
            "/execute",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Authorization,Content-Type",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)
        self.assertIn("Authorization", response.headers["Access-Control-Allow-Headers"])

    def test_execute_preflight_allows_vercel_preview_origins(self):
        origin = "https://stela-ai-git-main-stelaai.vercel.app"
        response = self.client.options(
            "/execute",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Authorization,Content-Type",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)

    def test_execute_rejects_missing_authentication(self):
        with patch.object(backend_app, "run_code") as run_code:
            response = self.client.post(
                "/execute",
                json={"language": "python", "code": "print(1)"},
            )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json["error"], "Authentication required")
        run_code.assert_not_called()

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    @patch.object(
        backend_app,
        "run_code",
        return_value=ExecutionResult(0, "2\n", ""),
    )
    def test_execute_returns_compatible_result_shape(self, run_code, _verify_user):
        response = self.client.post(
            "/execute",
            headers={"Authorization": "Bearer valid-token"},
            json={"language": "py", "code": "print(1 + 1)", "input": ""},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json,
            {
                "result": "2\n",
                "stdout": "2\n",
                "stderr": "",
                "error": "",
                "exitCode": 0,
            },
        )
        run_code.assert_called_once_with("print(1 + 1)", "python", "")

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    def test_execute_rejects_unsupported_language(self, _verify_user):
        with patch.object(backend_app, "run_code") as run_code:
            response = self.client.post(
                "/execute",
                headers={"Authorization": "Bearer valid-token"},
                json={"language": "ruby", "code": "puts 1"},
            )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json["error"], "Unsupported language: ruby")
        run_code.assert_not_called()

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    def test_execute_rejects_non_string_source(self, _verify_user):
        response = self.client.post(
            "/execute",
            headers={"Authorization": "Bearer valid-token"},
            json={"language": "python", "code": ["print(1)"]},
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json["error"], "Code, language, and input must be strings")

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    @patch.object(
        backend_app,
        "run_code",
        return_value=ExecutionResult(1, "", ""),
    )
    def test_nonzero_exit_without_stderr_has_an_explicit_error(self, _run_code, _verify_user):
        response = self.client.post(
            "/execute",
            headers={"Authorization": "Bearer valid-token"},
            json={"language": "python", "code": "raise SystemExit(1)"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["error"], "Process exited with code 1")
        self.assertEqual(response.json["exitCode"], 1)

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    def test_execute_rejects_oversized_source_before_allocating_sandbox(self, _verify_user):
        with patch.object(backend_app, "MAX_SOURCE_CHARS", 4), patch.object(
            backend_app, "run_code"
        ) as run_code:
            response = self.client.post(
                "/execute",
                headers={"Authorization": "Bearer valid-token"},
                json={"language": "python", "code": "print(1)"},
            )

        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.json["error"], "Code too large")
        run_code.assert_not_called()

    @patch.object(backend_app, "_verify_user", return_value={"user_id": "user-123"})
    @patch.object(backend_app, "run_code", side_effect=RuntimeError("provider unavailable"))
    def test_sandbox_failure_is_logged_and_returned_as_service_error(
        self,
        _run_code,
        _verify_user,
    ):
        with self.assertLogs(backend_app.app.logger, level="ERROR"):
            response = self.client.post(
                "/execute",
                headers={"Authorization": "Bearer valid-token"},
                json={"language": "python", "code": "print(1)"},
            )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json["error"], "Execution service unavailable")


if __name__ == "__main__":
    unittest.main()
