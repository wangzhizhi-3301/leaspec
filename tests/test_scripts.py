"""Regression tests against real scripts and disposable project directories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH_BIN", "bash")
START = b"<!-- LEASPEC-BOOTSTRAP-START -->\n"
END = b"<!-- LEASPEC-BOOTSTRAP-END -->\n"


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="leaspec-tests-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project with spaces"
        self.project.mkdir()

    def run_bash(self, *args, **kwargs):
        return subprocess.run(
            [BASH, *map(str, args)], capture_output=True, text=True,
            cwd=self.project, timeout=30, **kwargs,
        )

    def script(self, name, *args):
        return self.run_bash(ROOT / "scripts" / name, *args)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def update_context(self, contents):
        (self.project / "leaspec").mkdir(exist_ok=True)
        context = self.project / "AGENTS.md"
        context.write_bytes(contents)
        result = self.script("install.sh", "--update", "--non-interactive", self.project)
        return context, result

    def test_helper_cli_numbering(self):
        root = self.project / "specs with spaces"
        result = self.script("helpers.sh", "get_next_change_number", root)
        self.assert_success(result)
        self.assertEqual(result.stdout, "001")
        for name in ("001-first", "009-latest", "unrelated"):
            (root / "changes" / name).mkdir(parents=True)
        result = self.script("helpers.sh", "get_next_change_number", root)
        self.assert_success(result)
        self.assertEqual(result.stdout, "010")

    def test_helper_cli_default_directory(self):
        (self.project / "leaspec/changes/002-example").mkdir(parents=True)
        result = self.script("helpers.sh", "get_next_change_number")
        self.assert_success(result)
        self.assertEqual(result.stdout, "003")

    def test_helper_source_is_silent_and_callable(self):
        result = self.run_bash("-c", 'source "$1"', "_", ROOT / "scripts/helpers.sh")
        self.assert_success(result)
        self.assertEqual(result.stdout, "")
        result = self.run_bash("-c", 'source "$1"; get_next_change_number', "_", ROOT / "scripts/helpers.sh")
        self.assert_success(result)
        self.assertEqual(result.stdout, "001")

    def test_helper_rejects_unknown_commands_and_extra_arguments(self):
        for args in ((), ("atomic_write", "text", "unexpected-file"), ("get_next_change_number", ".", "extra")):
            with self.subTest(args=args):
                result = self.script("helpers.sh", *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("helpers.sh get_next_change_number", result.stderr)
        self.assertFalse((self.project / "unexpected-file").exists())

    def test_bootstrap_update_preserves_outside_bytes_and_is_idempotent(self):
        prefix = b"User rules\n\\slashes and -n\n"
        source = (ROOT / "agents/codex/bootstrap.md").read_bytes()
        new_block = source[source.index(START):source.index(END) + len(END)]
        for suffix in (b"Last user rule\n", b"Last user rule", b"", b"\r\nChinese: \xe4\xb8\xad\xe6\x96\x87\r\n"):
            with self.subTest(suffix=suffix):
                context, result = self.update_context(prefix + START + b"Old block\n" + END + suffix)
                self.assert_success(result)
                expected = prefix + new_block + suffix
                self.assertEqual(context.read_bytes(), expected)
                self.assert_success(self.script("install.sh", "--update", "--non-interactive", self.project))
                self.assertEqual(context.read_bytes(), expected)
                self.assertEqual(list(self.project.glob("AGENTS.md.leaspec.*")), [])

    def test_bootstrap_update_refuses_malformed_markers(self):
        cases = (
            START + b"Keep user rules\n",
            END + b"Keep user rules\n",
            END + START,
            START + START + END,
            START + END + END,
            START + END + START + END,
            START + b"Old\n" + START + END + END,
        )
        for contents in cases:
            with self.subTest(contents=contents):
                context, result = self.update_context(contents)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(context.read_bytes(), contents)
                self.assertEqual(list(self.project.glob("AGENTS.md.leaspec.*")), [])

    def test_bootstrap_without_markers_is_appended(self):
        original = b"Keep user rules without newline"
        context, result = self.update_context(original)
        self.assert_success(result)
        self.assertEqual(context.read_bytes(), original + b"\n" + (ROOT / "agents/codex/bootstrap.md").read_bytes())

    def test_bootstrap_preserves_symlink_and_permissions(self):
        (self.project / "leaspec").mkdir()
        target = self.project / "rules.md"
        target.write_bytes(b"Keep\n" + START + b"Old\n" + END + b"Last rule")
        target.chmod(0o640)
        context = self.project / "AGENTS.md"
        context.symlink_to("rules.md")
        result = self.script("install.sh", "--update", "--non-interactive", self.project)
        self.assert_success(result)
        self.assertTrue(context.is_symlink())
        self.assertTrue(target.read_bytes().endswith(b"Last rule"))
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_yaml_metadata_round_trips(self):
        values = (
            "", 'say "hello"', "it's a project", r"C:\new\folder",
            "first\nsecond\n", "tab\tcarriage\rreturn", "中文: # description",
            "".join(chr(code) for code in range(1, 32)) + chr(127),
            "".join(chr(code) for code in range(128, 160)) + "\u2028\u2029",
        )
        for index, value in enumerate(values):
            with self.subTest(value=value):
                project = self.project / str(index)
                project.mkdir()
                result = self.script(
                    "init.sh", "--non-interactive", "--name", value or "empty-desc",
                    "--description", value, "--version", value, project,
                )
                self.assert_success(result)
                config = yaml.safe_load((project / "leaspec/config.yaml").read_text())
                self.assertEqual(config["version"], value or "1.0")
                self.assertEqual(config["project"]["name"], value or "empty-desc")
                self.assertEqual(config["project"]["description"], value)
                self.assertIs(config["git"]["track_leaspec"], True)
                self.assertIs(config["git"]["track_agent_dirs"], False)


if __name__ == "__main__":
    unittest.main()
