import logging
import os
import re
import threading
import time
from collections import defaultdict, deque
from typing import Any

from flask import Flask, jsonify, request
from flask_cors import CORS
from google.auth import exceptions as google_auth_exceptions
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2.id_token import verify_firebase_token
from werkzeug.exceptions import RequestEntityTooLarge

from roles import Admin, Faculty, Student
from sandbox_runner import ExecutionResult, normalize_language, run_code

app = Flask(__name__)

FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "stela23-f9a52")
MAX_REQUEST_BYTES = int(os.environ.get("MAX_REQUEST_BYTES", "200000"))
MAX_SOURCE_CHARS = int(os.environ.get("MAX_SOURCE_CHARS", "50000"))
MAX_STDIN_CHARS = int(os.environ.get("MAX_STDIN_CHARS", "20000"))
RATE_LIMIT_WINDOW_SECONDS = int(os.environ.get("RATE_LIMIT_WINDOW_SECONDS", "60"))
RATE_LIMIT_MAX_REQUESTS = int(os.environ.get("RATE_LIMIT_MAX_REQUESTS", "20"))
MAX_CONCURRENT_EXECUTIONS = int(os.environ.get("MAX_CONCURRENT_EXECUTIONS", "4"))

app.config["MAX_CONTENT_LENGTH"] = MAX_REQUEST_BYTES

configured_origins = os.environ.get("ALLOWED_ORIGINS")
allowed_origins: list[str | re.Pattern[str]] = (
    [origin.strip() for origin in configured_origins.split(",") if origin.strip()]
    if configured_origins
    else [
        re.compile(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"),
        "https://stela4.dic-igdtuw.com",
        "https://stela-ai.vercel.app",
        "https://stelaai.vercel.app",
        re.compile(r"^https://[a-z0-9-]+\.vercel\.app$"),
    ]
)
CORS(
    app,
    resources={
        r"/*": {
            "origins": allowed_origins,
            "methods": ["GET", "POST", "OPTIONS"],
            "allow_headers": ["Content-Type", "Authorization"],
        }
    },
)

_execution_slots = threading.BoundedSemaphore(max(1, MAX_CONCURRENT_EXECUTIONS))
_rate_limit_lock = threading.Lock()
_rate_limit_buckets: defaultdict[str, deque[float]] = defaultdict(deque)


def _response(
    result: str = "",
    stdout: str = "",
    stderr: str = "",
    error: str = "",
    exit_code: int = 1,
) -> dict[str, Any]:
    return {
        "result": result,
        "stdout": stdout,
        "stderr": stderr,
        "error": error,
        "exitCode": exit_code,
    }


@app.errorhandler(RequestEntityTooLarge)
def request_too_large(_error: RequestEntityTooLarge):
    message = "Request too large"
    return jsonify(_response(stderr=message, error=message, exit_code=413)), 413


@app.route("/", methods=["GET"])
def health():
    return jsonify(
        {
            "status": "ok",
            "service": "stela-exec-backend",
            "executeEndpoint": "/execute",
        }
    )


@app.route("/dashboard", methods=["POST"])
def dashboard():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "Expected a JSON object"}), 400

    username = data.get("username")
    email = data.get("email")
    role = data.get("role")
    if not isinstance(role, str):
        return jsonify({"error": "Invalid role"}), 400

    role_map = {"student": Student, "faculty": Faculty, "admin": Admin}
    if role.lower() not in role_map:
        return jsonify({"error": "Invalid role"}), 400

    user = role_map[role.lower()](username, email)
    return jsonify(user.get_dashboard())


def _verify_user(token: str) -> dict[str, Any]:
    return verify_firebase_token(
        token,
        GoogleRequest(timeout=5),
        audience=FIREBASE_PROJECT_ID,
    )


def _authenticated_user() -> tuple[str | None, tuple[Any, int] | None]:
    authorization = request.headers.get("Authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        message = "Authentication required"
        return None, (jsonify(_response(stderr=message, error=message, exit_code=401)), 401)

    try:
        claims = _verify_user(token.strip())
    except google_auth_exceptions.TransportError:
        app.logger.exception("Firebase token verification service is unavailable")
        message = "Authentication service unavailable"
        return None, (jsonify(_response(stderr=message, error=message, exit_code=503)), 503)
    except (ValueError, google_auth_exceptions.GoogleAuthError):
        message = "Invalid or expired authentication token"
        return None, (jsonify(_response(stderr=message, error=message, exit_code=401)), 401)

    if not isinstance(claims, dict):
        message = "Invalid or expired authentication token"
        return None, (jsonify(_response(stderr=message, error=message, exit_code=401)), 401)

    user_id = claims.get("user_id") or claims.get("sub")
    if not isinstance(user_id, str) or not user_id:
        message = "Invalid authentication token"
        return None, (jsonify(_response(stderr=message, error=message, exit_code=401)), 401)
    return user_id, None


def _check_rate_limit(user_id: str) -> tuple[bool, int]:
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW_SECONDS
    with _rate_limit_lock:
        bucket = _rate_limit_buckets[user_id]
        while bucket and bucket[0] < window_start:
            bucket.popleft()

        if len(bucket) >= RATE_LIMIT_MAX_REQUESTS:
            retry_after = max(1, int(bucket[0] + RATE_LIMIT_WINDOW_SECONDS - now))
            return False, retry_after

        bucket.append(now)
        if len(_rate_limit_buckets) > 5000:
            stale_users = [
                key
                for key, timestamps in _rate_limit_buckets.items()
                if not timestamps or timestamps[-1] < window_start
            ]
            for key in stale_users:
                _rate_limit_buckets.pop(key, None)

    return True, 0


def _error_response(message: str, exit_code: int, status_code: int):
    return jsonify(_response(stderr=message, error=message, exit_code=exit_code)), status_code


@app.route("/execute", methods=["POST"])
def execute():
    user_id, authentication_error = _authenticated_user()
    if authentication_error is not None:
        return authentication_error
    if user_id is None:
        return _error_response("Authentication required", 401, 401)

    allowed, retry_after = _check_rate_limit(user_id)
    if not allowed:
        response, status = _error_response("Rate limit exceeded", 429, 429)
        response.headers["Retry-After"] = str(retry_after)
        return response, status

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return _error_response("Expected a JSON object", 400, 400)

    code = data.get("code", "")
    language = data.get("language", "python")
    stdin = data.get("input", data.get("stdin", ""))
    if not isinstance(code, str) or not isinstance(language, str) or not isinstance(stdin, str):
        return _error_response("Code, language, and input must be strings", 400, 400)

    code = code.replace("\r\n", "\n")
    language = language.strip().lower()
    stdin = stdin.replace("\r\n", "\n")
    try:
        language = normalize_language(language)
    except ValueError as error:
        return _error_response(str(error), 2, 400)

    if not code.strip():
        return _error_response("Empty code", 1, 400)
    if len(code) > MAX_SOURCE_CHARS:
        return _error_response("Code too large", 413, 413)
    if len(stdin) > MAX_STDIN_CHARS:
        return _error_response("Input too large", 413, 413)

    if not _execution_slots.acquire(blocking=False):
        return _error_response("Server busy. Try again shortly.", 429, 429)

    try:
        execution: ExecutionResult = run_code(code, language, stdin)
        error = ""
        if execution.exit_code:
            error = execution.stderr or f"Process exited with code {execution.exit_code}"
        return (
            jsonify(
                _response(
                    result=execution.stdout,
                    stdout=execution.stdout,
                    stderr=execution.stderr,
                    error=error,
                    exit_code=execution.exit_code,
                )
            ),
            200,
        )
    except Exception:
        app.logger.exception(
            "Sandbox execution failed for user %s using language %s",
            user_id,
            language,
        )
        return _error_response("Execution service unavailable", 503, 503)
    finally:
        _execution_slots.release()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port, debug=False)
