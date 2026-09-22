import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

from laya_server import SafetyClassifier, make_handler


class FakeAgent:
    def __init__(self, unsafe_probability=0.1, category="safe"):
        self.unsafe_probability = unsafe_probability
        self.category = category

    def predict(self, state, questions):
        return {
            "model": "fake-laya",
            "answers": {
                "unsafe": {"noul": self.unsafe_probability},
                "category": {"choice": self.category},
            },
        }


class SafetyClassifierTests(unittest.TestCase):
    def test_safe_decision(self):
        result = SafetyClassifier(FakeAgent()).classify("gardening tips")
        self.assertTrue(result["safe"])
        self.assertEqual(result["reason"], "Safe content")

    def test_unsafe_decision_uses_category_reason(self):
        result = SafetyClassifier(FakeAgent(0.91, "violence")).classify("violent report")
        self.assertFalse(result["safe"])
        self.assertEqual(result["reason"], "Violence or crisis")
        self.assertEqual(result["confidence"], 0.91)


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        classifier = SafetyClassifier(FakeAgent(0.8, "urgency"))
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(classifier))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_health(self):
        with urllib.request.urlopen(self.base_url + "/health") as response:
            self.assertEqual(json.load(response), {"status": "ready"})

    def test_classify(self):
        request = urllib.request.Request(
            self.base_url + "/v1/classify",
            data=json.dumps({"text": "Act now or everything is lost"}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            result = json.load(response)
        self.assertFalse(result["safe"])
        self.assertEqual(result["reason"], "Urgency pressure")

    def test_rejects_empty_text(self):
        request = urllib.request.Request(
            self.base_url + "/v1/classify",
            data=b'{"text":""}',
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as context:
            urllib.request.urlopen(request)
        self.assertEqual(context.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
