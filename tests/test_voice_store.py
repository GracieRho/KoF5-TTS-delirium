from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from kof5_tts.voice_store import SQLiteStore, StoreUnavailable, SupabaseStore, get_store


class SQLiteStoreTests(unittest.TestCase):
    def test_one_reservation_per_session_across_workers(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / "trial.sqlite"
            def compete(index):
                return SQLiteStore(path).create("same-browser", f"clone-{index}")

            with ThreadPoolExecutor(max_workers=8) as pool:
                self.assertEqual(sum(pool.map(compete, range(16))), 1)

            store = SQLiteStore(path)
            self.assertEqual(store.get("same-browser").state, "creating")
            self.assertIsNone(store.get("different-browser"))

    def test_stale_requests_cannot_modify_later_recording(self):
        with TemporaryDirectory() as folder:
            store = SQLiteStore(Path(folder) / "trial.sqlite")
            self.assertTrue(store.create("browser", "first"))
            self.assertTrue(store.transition("browser", "first", ("creating",), "ready", "id1"))
            self.assertFalse(store.transition("browser", "first", ("creating",), "ready", "id2"))
            self.assertFalse(store.clear("browser", "first", ("deleting",)))
            self.assertTrue(store.transition("browser", "first", ("ready",), "deleting", "id1"))
            self.assertTrue(store.clear("browser", "first", ("deleting",)))
            self.assertTrue(store.create("browser", "second"))
            self.assertFalse(store.clear("browser", "first", ("creating",)))
            self.assertFalse(store.transition("other-browser", "second", ("creating",), "ready", "id3"))
            self.assertEqual(store.get("browser").reference, "second")
            self.assertIsNone(store.get("browser").voice_id)


class HostedStoreTests(unittest.TestCase):
    def test_vercel_and_partial_hosted_config_never_fall_back_to_sqlite(self):
        for extra in ({"VERCEL": "1"}, {"FAVILIUM_SUPABASE_SERVICE_KEY": "key"}):
            with patch.dict(os.environ, {"FAVILIUM_DB_PATH": "/tmp/voices.db", **extra}, clear=True):
                with self.assertRaises(StoreUnavailable):
                    get_store()

    def test_postgrest_compare_and_set_filters_and_credentials(self):
        store = SupabaseStore("https://test.supabase.co/", "sb_secret_test")
        captured = []
        def respond(method, url, **kwargs):
            captured.append((method, kwargs))
            request = httpx.Request(method, url)
            return httpx.Response(200, json=[{"session_id": "s"}], request=request)

        with patch("kof5_tts.voice_store.httpx.request", side_effect=respond):
            self.assertTrue(store.create("s", "ref"))
            self.assertTrue(store.transition("s", "ref", ("verification", "creating"), "ready", "v"))
            self.assertTrue(store.clear("s", "ref", ("deleting",)))
        _, insert = captured[0]
        self.assertEqual(insert["params"]["on_conflict"], "session_id")
        self.assertIn("resolution=ignore-duplicates", insert["headers"]["Prefer"])
        for method, data in captured:
            self.assertNotIn("Authorization", data["headers"])
            self.assertEqual(data["headers"]["apikey"], "sb_secret_test")
            if method != "POST":
                self.assertEqual(data["params"]["session_id"], "eq.s")
                self.assertEqual(data["params"]["reference"], "eq.ref")
        self.assertEqual(captured[1][1]["params"]["state"], "in.(verification,creating)")
        self.assertEqual(captured[2][1]["params"]["state"], "in.(deleting)")

    def test_unchanged_and_failed_requests_have_distinct_outcomes(self):
        store = SupabaseStore("https://test.supabase.co", "jwt-service-role")
        request = httpx.Request("DELETE", store.endpoint)
        with patch("kof5_tts.voice_store.httpx.request") as call:
            call.return_value = httpx.Response(200, json=[], request=request)
            self.assertFalse(store.clear("s", "ref", ("deleting",)))
            self.assertEqual(call.call_args.kwargs["headers"]["Authorization"], "Bearer jwt-service-role")
            call.return_value = httpx.Response(503, text="details must not leak", request=request)
            with self.assertRaises(StoreUnavailable) as error:
                store.clear("s", "ref", ("deleting",))
            self.assertNotIn("details", str(error.exception))
