import asyncio
import io
import os
from dataclasses import dataclass

from vercel.sandbox import NetworkPolicy, Sandbox, SandboxResources, create_sandbox

EXECUTION_IMAGE = os.environ.get("EXECUTION_IMAGE", "stela-execution-runner:latest")
MAX_OUTPUT_CHARS = 32768
MAX_FILE_SIZE_BLOCKS = 65536

_LANGUAGE_ALIASES = {
    "py": "python",
    "js": "javascript",
    "node": "javascript",
    "c++": "cpp",
}
SUPPORTED_LANGUAGES = {"python", "javascript", "c", "cpp", "java", "dart"}


@dataclass(frozen=True)
class ExecutionResult:
    exit_code: int
    stdout: str
    stderr: str


class _LimitedOutput(io.StringIO):
    def __init__(self, limit: int):
        super().__init__()
        self.limit = limit
        self.truncated = False

    def write(self, text: str) -> int:
        remaining = max(0, self.limit - self.tell())
        super().write(text[:remaining])
        if len(text) > remaining:
            self.truncated = True
        return len(text)

    def value(self) -> str:
        output = self.getvalue()
        if self.truncated:
            return f"{output}\n[output truncated]"
        return output


def normalize_language(language: str) -> str:
    normalized = _LANGUAGE_ALIASES.get(language, language)
    if normalized not in SUPPORTED_LANGUAGES:
        raise ValueError(f"Unsupported language: {language}")
    return normalized


def _timeout_seconds() -> int:
    return min(max(int(os.environ.get("CODE_EXEC_TIMEOUT_SECONDS", "8")), 1), 10)


async def _run_process(
    sandbox: Sandbox,
    command: str,
    timeout_seconds: int,
) -> ExecutionResult:
    stdout = _LimitedOutput(MAX_OUTPUT_CHARS)
    stderr = _LimitedOutput(MAX_OUTPUT_CHARS)
    limited_command = (
        f"ulimit -c 0 && ulimit -f {MAX_FILE_SIZE_BLOCKS} "
        f"&& ulimit -u 256 && ulimit -n 256 && {command}"
    )

    try:
        process = await asyncio.wait_for(
            sandbox.run_process(
                "bash",
                ["-c", limited_command],
                cwd="/tmp",
                kill_after=timeout_seconds,
                stdout=stdout,
                stderr=stderr,
            ),
            timeout=timeout_seconds + 3,
        )
    except asyncio.TimeoutError:
        return ExecutionResult(124, stdout.value(), "Time limit exceeded")

    exit_code = process.returncode
    error = stderr.value()
    if exit_code in (124, 137, -9) and not error:
        error = "Time limit exceeded"
    return ExecutionResult(exit_code, stdout.value(), error)


async def _run_in_sandbox(
    code: str,
    language: str,
    stdin: str,
    timeout_seconds: int,
) -> ExecutionResult:
    async with create_sandbox(
        image=EXECUTION_IMAGE,
        execution_time_limit=timeout_seconds + 30,
        resources=SandboxResources(vcpus=1, memory=2048),
        persistent=False,
        network_policy=NetworkPolicy.deny_all(),
        destroy=True,
    ) as sandbox:
        await sandbox.fs.write_text("/tmp/stdin.txt", stdin)

        if language == "python":
            source = "/tmp/main.py"
            await sandbox.fs.write_text(source, code)
            command = "exec python3 /tmp/main.py < /tmp/stdin.txt"

        elif language == "javascript":
            source = "/tmp/main.js"
            await sandbox.fs.write_text(source, code)
            command = "exec node /tmp/main.js < /tmp/stdin.txt"

        elif language in ("c", "cpp"):
            extension = "c" if language == "c" else "cpp"
            source = f"/tmp/main.{extension}"
            await sandbox.fs.write_text(source, code)
            compiler = "gcc" if language == "c" else "g++"
            flags = ["-O2"] if language == "c" else ["-std=c++17", "-O2"]
            compile_command = " ".join([compiler, *flags, source, "-o", "/tmp/main"])
            compilation = await _run_process(sandbox, compile_command, timeout_seconds)
            if compilation.exit_code != 0:
                return compilation
            command = "exec /tmp/main < /tmp/stdin.txt"

        elif language == "java":
            source = "/tmp/Main.java"
            await sandbox.fs.write_text(source, code)
            compilation = await _run_process(
                sandbox,
                "exec javac /tmp/Main.java",
                timeout_seconds,
            )
            if compilation.exit_code != 0:
                return compilation
            command = "exec java -cp /tmp Main < /tmp/stdin.txt"

        else:
            source = "/tmp/main.dart"
            await sandbox.fs.write_text(source, code)
            command = "exec dart /tmp/main.dart < /tmp/stdin.txt"

        return await _run_process(sandbox, command, timeout_seconds)


def run_code(code: str, language: str, stdin: str) -> ExecutionResult:
    language = normalize_language(language)
    return asyncio.run(_run_in_sandbox(code, language, stdin, _timeout_seconds()))
