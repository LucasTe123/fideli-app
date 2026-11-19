import io
import json
import unittest
import urllib.error
from unittest.mock import patch

import gemini_bot


class GeminiTests(unittest.TestCase):
    def test_request_uses_header_and_only_supplied_text(self):
        def respond(request, **kwargs):
            self.assertNotIn('test-key', request.full_url)
            self.assertEqual(request.get_header('X-goog-api-key'), 'test-key')
            data = json.loads(request.data)
            self.assertEqual(data['contents'], [{'role': 'user', 'parts': [{'text': 'hola'}]}])
            return io.BytesIO(json.dumps({'candidates': [{'content': {'parts': [{'text': 'Hola'}]}}]}).encode())
        with patch.object(gemini_bot, 'api_key', return_value='test-key'), patch.object(gemini_bot.urllib.request, 'urlopen', side_effect=respond):
            self.assertEqual(gemini_bot.generate_reply('hola'), 'Hola')

    def test_quota_failure_is_readable_and_does_not_leak_body(self):
        error = urllib.error.HTTPError('https://example.invalid', 429, 'quota', {}, None)
        with patch.object(gemini_bot, 'api_key', return_value='test-key'), patch.object(gemini_bot.urllib.request, 'urlopen', side_effect=error):
            with self.assertRaisesRegex(gemini_bot.GeminiError, 'límite gratuito'):
                gemini_bot.generate_reply('hola')

    def test_transient_timeout_is_retried_and_model_uses_minimal_thinking(self):
        result = {'candidates': [{'content': {'parts': [{'text': 'Hola'}]}}]}
        def success(request, **kwargs):
            self.assertEqual(kwargs['timeout'], 60)
            data = json.loads(request.data)
            self.assertEqual(data['generationConfig']['thinkingConfig']['thinkingLevel'], 'minimal')
            return io.BytesIO(json.dumps(result).encode())
        calls = 0
        def request(req, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1: raise TimeoutError()
            return success(req, **kwargs)
        with patch.object(gemini_bot, 'api_key', return_value='test-key'), patch.object(gemini_bot.urllib.request, 'urlopen', side_effect=request), patch.object(gemini_bot.time, 'sleep'):
            self.assertEqual(gemini_bot.generate_reply('hola'), 'Hola')
        self.assertEqual(calls, 2)

    def test_missing_key_does_not_make_request(self):
        with patch.object(gemini_bot, 'api_key', return_value=''), patch.object(gemini_bot.urllib.request, 'urlopen') as send:
            with self.assertRaises(gemini_bot.GeminiError):
                gemini_bot.generate_reply('hola')
            send.assert_not_called()


if __name__ == '__main__':
    unittest.main()
