import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import main  # noqa: E402


class MainToolTests(unittest.TestCase):
    def test_entry_patch_requires_expected_instruction(self):
        profile = main.PATCH_PROFILES[0]
        binary = bytearray(profile.patch_offset + 4)
        struct.pack_into('<I', binary, 0, 0xFEEDFACF)
        binary[profile.patch_offset:profile.patch_offset + 4] = profile.original
        patched = main.patched_binary(bytes(binary), profile, verify_hash=False)
        self.assertEqual(patched[profile.patch_offset:profile.patch_offset + 4], main.NOP)

    def test_entry_patch_rejects_wrong_instruction(self):
        profile = main.PATCH_PROFILES[0]
        binary = bytearray(profile.patch_offset + 4)
        struct.pack_into('<I', binary, 0, 0xFEEDFACF)
        with self.assertRaises(ValueError):
            main.patched_binary(bytes(binary), profile, verify_hash=False)

    def test_ad_removal_options_are_parsed(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.ipa'
            output = Path(directory) / 'output.ipa'
            args = main.parse_args([
                str(source), str(output), '--remove-ads',
                '--hide-promotional-tabs',
            ])
        self.assertTrue(args.remove_ads)
        self.assertTrue(args.hide_promotional_tabs)

    def test_primary_login_mode_is_parsed(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.ipa'
            output = Path(directory) / 'output.ipa'
            args = main.parse_args([
                str(source), str(output), '--primary-login',
            ])
        self.assertTrue(args.primary_login)

    def test_entry_only_rejects_primary_login(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.ipa'
            output = Path(directory) / 'output.ipa'
            with self.assertRaises(SystemExit):
                main.parse_args([
                    str(source), str(output), '--entry-only', '--primary-login',
                ])

    def test_entry_only_rejects_ad_removal(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.ipa'
            output = Path(directory) / 'output.ipa'
            with self.assertRaises(SystemExit):
                main.parse_args([
                    str(source), str(output), '--entry-only', '--remove-ads',
                ])


if __name__ == '__main__':
    unittest.main()
