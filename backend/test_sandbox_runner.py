import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, Mock, patch

from vercel.sandbox import NetworkPolicy

import sandbox_runner


class SandboxRunnerTests(unittest.TestCase):
    def test_python_runs_only_in_network_disabled_disposable_sandbox(self):
        sandbox = Mock()
        sandbox.fs.write_text = AsyncMock()
        commands = []

        async def run_process(command, args, **kwargs):
            commands.append((command, args, kwargs))
            kwargs["stdout"].write("sandbox output\n")
            return SimpleNamespace(returncode=0)

        sandbox.run_process = AsyncMock(side_effect=run_process)
        manager = MagicMock()
        manager.__aenter__ = AsyncMock(return_value=sandbox)
        manager.__aexit__ = AsyncMock(return_value=False)

        with patch.object(sandbox_runner, "create_sandbox", return_value=manager) as create:
            result = sandbox_runner.run_code("print(1)", "python", "input")

        options = create.call_args.kwargs
        self.assertEqual(options["image"], sandbox_runner.EXECUTION_IMAGE)
        self.assertEqual(options["network_policy"], NetworkPolicy.deny_all())
        self.assertFalse(options["persistent"])
        self.assertTrue(options["destroy"])
        self.assertEqual(options["resources"].vcpus, 1)
        self.assertEqual(options["resources"].memory, 2048)
        sandbox.fs.write_text.assert_any_await("/tmp/main.py", "print(1)")
        sandbox.fs.write_text.assert_any_await("/tmp/stdin.txt", "input")
        self.assertEqual(commands[0][0], "bash")
        self.assertEqual(
            commands[0][1],
            [
                "-c",
                "ulimit -c 0 && ulimit -f 65536 && ulimit -u 256 "
                "&& ulimit -n 256 && exec python3 /tmp/main.py < /tmp/stdin.txt",
            ],
        )
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.stdout, "sandbox output\n")
        manager.__aexit__.assert_awaited_once()

    def test_cpp_compiles_and_runs_in_the_sandbox(self):
        sandbox = Mock()
        sandbox.fs.write_text = AsyncMock()
        commands = []

        async def run_process(command, args, **kwargs):
            commands.append(args[1])
            return SimpleNamespace(returncode=0)

        sandbox.run_process = AsyncMock(side_effect=run_process)
        manager = MagicMock()
        manager.__aenter__ = AsyncMock(return_value=sandbox)
        manager.__aexit__ = AsyncMock(return_value=False)

        with patch.object(sandbox_runner, "create_sandbox", return_value=manager):
            result = sandbox_runner.run_code("int main() {}", "cpp", "")

        self.assertEqual(
            commands,
            [
                "ulimit -c 0 && ulimit -f 65536 && ulimit -u 256 "
                "&& ulimit -n 256 && g++ -std=c++17 -O2 /tmp/main.cpp -o /tmp/main",
                "ulimit -c 0 && ulimit -f 65536 && ulimit -u 256 "
                "&& ulimit -n 256 && exec /tmp/main < /tmp/stdin.txt",
            ],
        )
        self.assertEqual(result.exit_code, 0)

    def test_output_is_truncated_at_the_configured_limit(self):
        output = sandbox_runner._LimitedOutput(4)

        output.write("abcdef")

        self.assertEqual(output.value(), "abcd\n[output truncated]")

    def test_language_aliases_are_normalized(self):
        self.assertEqual(sandbox_runner.normalize_language("js"), "javascript")
        self.assertEqual(sandbox_runner.normalize_language("c++"), "cpp")
        with self.assertRaisesRegex(ValueError, "Unsupported language"):
            sandbox_runner.normalize_language("ruby")


if __name__ == "__main__":
    unittest.main()
