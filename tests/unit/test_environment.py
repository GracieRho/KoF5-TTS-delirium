import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from kof5_tts.environment import load_server_env


class ServerEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(os.environ, {}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)

    def test_reads_provider_keys_only_without_executing_shell(self):
        (self.root / ".env").write_text(
            "# test keys\nexport OPENAI_API_KEY='fake-openai'\n"
            'ELEVENLABS_API_KEY="fake-eleven"\n'
            "DEEPGRAM_API_KEY=$(echo never-execute)\n"
            "VERCEL_TOKEN=fake-admin\nSUPABASE_ACCESS_TOKEN=fake-management\nOPENROUTER_API_KEY=fake-openrouter\nKOF5_LOCAL_STUDIO=1\nAIHUB_APIKEY=fake-aihub\n"
        )
        load_server_env(self.root)
        self.assertEqual(dict(os.environ), {
            "OPENAI_API_KEY": "fake-openai",
            "OPENROUTER_API_KEY": "fake-openrouter",
            "ELEVENLABS_API_KEY": "fake-eleven",
            "DEEPGRAM_API_KEY": "$(echo never-execute)",
        })

    def test_research_loads_only_requested_provider_and_rejects_management_tokens(self):
        (self.root / '.env').write_text('OPENROUTER_API_KEY=free-key\nOPENAI_API_KEY=other-provider\nSUPABASE_ACCESS_TOKEN=management\n')
        load_server_env(self.root, keys=('OPENROUTER_API_KEY',))
        self.assertEqual(dict(os.environ), {'OPENROUTER_API_KEY': 'free-key'})
        with self.assertRaises(ValueError):
            load_server_env(self.root, keys=('SUPABASE_ACCESS_TOKEN',))

    def test_process_environment_has_priority_including_explicit_empty(self):
        (self.root / ".env").write_text("OPENAI_API_KEY=file-key\nELEVENLABS_API_KEY=file-key\n")
        os.environ.update(OPENAI_API_KEY="process-key", ELEVENLABS_API_KEY="")
        load_server_env(self.root)
        self.assertEqual(os.environ["OPENAI_API_KEY"], "process-key")
        self.assertEqual(os.environ["ELEVENLABS_API_KEY"], "")

    def test_missing_file_and_empty_values_do_not_set_keys(self):
        load_server_env(self.root)
        (self.root / ".env").write_text("OPENAI_API_KEY=\nELEVENLABS_API_KEY=''\n")
        load_server_env(self.root)
        self.assertEqual(dict(os.environ), {})

    def test_worktree_overrides_root_and_root_supplies_missing_keys(self):
        worktree = self.root / ".worktrees" / "task"
        worktree.mkdir(parents=True)
        (self.root / ".env").write_text("OPENAI_API_KEY=root-key\nELEVENLABS_API_KEY=root-eleven\n")
        load_server_env(worktree)
        self.assertEqual(os.environ["OPENAI_API_KEY"], "root-key")
        os.environ.clear()
        (worktree / ".env").write_text("OPENAI_API_KEY=worktree-key\n")
        load_server_env(worktree)
        self.assertEqual(os.environ["OPENAI_API_KEY"], "worktree-key")
        self.assertEqual(os.environ["ELEVENLABS_API_KEY"], "root-eleven")

    def test_vercel_never_loads_local_file(self):
        (self.root / ".env").write_text("OPENAI_API_KEY=local-key\n")
        os.environ["VERCEL"] = "1"
        load_server_env(self.root)
        self.assertNotIn("OPENAI_API_KEY", os.environ)

    def test_api_startup_loads_provider_keys_only_for_local_server(self):
        (self.root / ".env").write_text(
            "OPENAI_API_KEY=file-openai\nELEVENLABS_API_KEY=file-eleven\n"
            "DEEPGRAM_API_KEY=file-deepgram\nOPENROUTER_API_KEY=research-only\nVERCEL_TOKEN=management\n"
        )
        script = """
import os, sys
from pathlib import Path
from unittest.mock import patch
from kof5_tts.environment import load_server_env
with patch('kof5_tts.environment.load_server_env', side_effect=lambda **kw: load_server_env(Path(sys.argv[1]), **kw)):
    import kof5_tts.api
assert os.environ.get('OPENAI_API_KEY') == ('process-key' if not os.environ.get('VERCEL') else None)
assert os.environ.get('ELEVENLABS_API_KEY') == ('file-eleven' if not os.environ.get('VERCEL') else None)
assert os.environ.get('DEEPGRAM_API_KEY') == ('file-deepgram' if not os.environ.get('VERCEL') else None)
assert 'VERCEL_TOKEN' not in os.environ
assert 'OPENROUTER_API_KEY' not in os.environ
"""
        for vercel in (False, True):
            env = {'PYTHONPATH': str(Path(__file__).resolve().parents[2] / 'src')}
            env.update({'VERCEL': '1'} if vercel else {'OPENAI_API_KEY': 'process-key'})
            result = subprocess.run([sys.executable, '-c', script, str(self.root)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
