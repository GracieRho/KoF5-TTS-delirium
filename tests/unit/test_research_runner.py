import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import run_research


class ResearchRunnerTests(unittest.TestCase):
    def test_enables_only_loopback_research_server(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["run_research"]), \
                patch.object(run_research.uvicorn, "run") as server:
            run_research.main()
            self.assertEqual(os.environ["KOF5_RESEARCH_ENABLED"], "1")
            server.assert_called_once_with("kof5_tts.api:app", host="127.0.0.1", port=8767)

    def test_rejects_vercel_and_invalid_port_without_starting(self):
        for environment, arguments in [({"VERCEL": "1"}, []), ({}, ["--port", "0"])]:
            with patch.dict(os.environ, environment, clear=True), \
                    patch.object(sys, "argv", ["run_research", *arguments]), \
                    patch.object(run_research.uvicorn, "run") as server, \
                    patch("sys.stderr"):
                with self.assertRaises(SystemExit):
                    run_research.main()
                server.assert_not_called()


if __name__ == "__main__":
    unittest.main()
