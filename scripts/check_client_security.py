"""Source-policy checks; these do not execute or validate the Flutter app."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ClientBoundaryTests(unittest.TestCase):
    def test_no_private_key_files_in_client_tree(self):
        # Report counts only: failed checks must not echo credential material.
        candidates = list((ROOT / 'assets').rglob('*')) + list((ROOT / 'lib').rglob('*'))
        count = sum(
            b'-----BEGIN PRIVATE KEY-----' in p.read_bytes()
            for p in candidates if p.is_file()
        )
        self.assertEqual(count, 0, 'Client tree contains private-key material')

    def test_no_service_account_asset_loading(self):
        source = (ROOT / 'lib/main.dart').read_text()
        self.assertFalse('rootBundle.loadString' in source, 'Startup loads a credential asset')
        self.assertFalse('firebase-adminsdk' in (ROOT / 'pubspec.yaml').read_text())

    def test_no_privileged_messaging_client(self):
        source = (ROOT / 'lib/notification.dart').read_text()
        for marker in ('ServiceAccountCredentials', 'clientViaServiceAccount', 'fcm.googleapis.com'):
            self.assertFalse(marker in source, 'Privileged messaging code remains in the client')


if __name__ == '__main__':
    unittest.main(verbosity=2)
