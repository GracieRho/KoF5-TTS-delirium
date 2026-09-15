"""No-network regression checks for the local Supabase HTTP smoke boundary."""

import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_http_smoke as smoke


class LocalHttpSmokeBoundaryTest(unittest.TestCase):
    def test_cli_status_uses_the_task_checkout(self):
        with patch.object(smoke.subprocess, "run", return_value=SimpleNamespace(stdout="API_URL=http://127.0.0.1:54341")) as run:
            smoke.local_keys()
        self.assertEqual(run.call_args.kwargs["cwd"], smoke.ROOT)

    def test_wrong_api_is_rejected_before_creating_an_account(self):
        keys = {"API_URL": "http://127.0.0.1:54322"}
        with patch.object(smoke, "local_keys", return_value=keys), patch.object(smoke, "request") as send:
            with self.assertRaises(ValueError):
                smoke.main()
        send.assert_not_called()

    def test_lost_create_response_still_deletes_this_email_user(self):
        patient = UUID("00000000-0000-4000-8000-000000000701")
        email_suffix = UUID("00000000-0000-4000-8000-000000000702")
        user = UUID("00000000-0000-4000-8000-000000000703")
        email = f"kof5-local-{email_suffix.hex}@example.invalid"
        calls = []

        def fake_sql(command):
            calls.append(command)
            return str(user) if command == f"SELECT id FROM auth.users WHERE email='{email}';" else ""

        def fake_request(url, method, *_args, **_kwargs):
            calls.append((method, url))
            if method == "POST":
                raise TimeoutError("response lost after server created account")
            return 204, None

        keys = {"API_URL": "http://127.0.0.1:54341", "PUBLISHABLE_KEY": "sb_publishable_local", "SERVICE_ROLE_KEY": "local-admin"}
        with patch.object(smoke, "local_keys", return_value=keys), \
             patch.object(smoke, "uuid4", side_effect=[patient, email_suffix]), \
             patch.object(smoke, "sql", side_effect=fake_sql), \
             patch.object(smoke, "request", side_effect=fake_request):
            with self.assertRaises(TimeoutError):
                smoke.main()

        self.assertIn(("DELETE", f"http://127.0.0.1:54341/auth/v1/admin/users/{user}"), calls)
        self.assertIn(f"SELECT id FROM auth.users WHERE email='{email}';", calls)


if __name__ == "__main__":
    unittest.main()
