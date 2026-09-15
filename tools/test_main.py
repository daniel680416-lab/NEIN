import plistlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import main  # noqa: E402


class MainToolTests(unittest.TestCase):
    def sample_info(self):
        icons = {
            'CFBundlePrimaryIcon': {
                'CFBundleIconFiles': ['basic_default60x60'],
                'CFBundleIconName': 'basic_default',
            },
            'CFBundleAlternateIcons': {
                'design_deep_blue': {'CFBundleIconName': 'design_deep_blue'},
                'design_simple_banana': {'CFBundleIconName': 'design_simple_banana'},
            },
        }
        return {
            'CFBundleIdentifier': 'jp.naver.line',
            'CFBundleShortVersionString': '26.14.0',
            'CFBundleDisplayName': 'LINE',
            'CFBundleName': 'LINE',
            'CFBundleURLTypes': [{
                'CFBundleURLSchemes': ['line', 'lineauth2'],
            }],
            'CFBundleURLTypes~ipad': [{
                'CFBundleURLSchemes': ['line'],
            }],
            'CFBundleIcons': icons,
            'CFBundleIcons~ipad': icons,
        }

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

    def test_embedded_extensions_and_watch_app_are_excluded(self):
        names = [
            'Payload/LINE.app/Info.plist',
            'Payload/LINE.app/Extensions/LineAppIntentsExtension.appex/',
            'Payload/LINE.app/Extensions/LineAppIntentsExtension.appex/Info.plist',
            'Payload/LINE.app/PlugIns/',
            'Payload/LINE.app/PlugIns/LineShareExtension.appex/Info.plist',
            'Payload/LINE.app/Watch/',
            'Payload/LINE.app/Watch/LineWatchKitApp.app/Info.plist',
        ]
        self.assertEqual(main.retained_archive_members(names), [
            'Payload/LINE.app/Info.plist',
        ])

    def test_output_info_plist_uses_default_bundle_id(self):
        source = self.sample_info()
        output = plistlib.loads(main.patched_info_plist(source, main.DEFAULT_ICON))
        self.assertEqual(output['CFBundleIdentifier'], 'kinta.ma.nein')
        self.assertEqual(output['CFBundleDisplayName'], 'NEIN')
        self.assertEqual(output['CFBundleName'], 'NEIN')
        self.assertNotIn('CFBundleURLTypes', output)
        self.assertNotIn('CFBundleURLTypes~ipad', output)
        self.assertEqual(
            output['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'],
            'design_simple_banana',
        )
        self.assertEqual(
            output['CFBundleIcons~ipad']['CFBundlePrimaryIcon']['CFBundleIconName'],
            'design_simple_banana',
        )
        self.assertEqual(source['CFBundleIdentifier'], 'jp.naver.line')
        self.assertEqual(output['CFBundleShortVersionString'], '26.14.0')
        self.assertEqual(
            source['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'],
            'basic_default',
        )

    def test_output_info_plist_accepts_available_custom_icon(self):
        output = plistlib.loads(main.patched_info_plist(
            self.sample_info(), 'design_deep_blue',
        ))
        self.assertEqual(
            output['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'],
            'design_deep_blue',
        )

    def test_output_info_plist_rejects_unknown_icon(self):
        with self.assertRaisesRegex(ValueError, 'Unknown app icon'):
            main.patched_info_plist(self.sample_info(), 'unknown_icon')

    def test_icon_argument_defaults_and_accepts_custom_value(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.ipa'
            output = Path(directory) / 'output.ipa'
            default_args = main.parse_args([str(source), str(output)])
            custom_args = main.parse_args([
                str(source), str(output), '--icon', 'design_deep_blue',
            ])
        self.assertEqual(default_args.icon, 'design_simple_banana')
        self.assertEqual(custom_args.icon, 'design_deep_blue')

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
