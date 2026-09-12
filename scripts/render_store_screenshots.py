#!/usr/bin/env python3
"""Render fixture-only real AppKit/SwiftUI views. Caller owns the Mac UI lease."""
from pathlib import Path
import os
import subprocess
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'dist/mas-20260905'
APP = Path(os.environ.get('PIC2LINK_SCREENSHOT_APP', '/private/tmp/codex-apple-tests/Pic2Link/mas-20260905/DerivedData/Build/Products/Debug/Pic2Link.app'))
LOCALES = dict(zip(
    ['en-US', 'zh-Hans', 'zh-Hant', 'ko', 'ja', 'ru', 'es-ES', 'pt-BR', 'th', 'hi', 'fr-FR', 'ar-SA', 'de-DE'],
    ['en', 'zh-Hans', 'zh-Hant', 'ko', 'ja', 'ru', 'es', 'pt', 'th', 'hi', 'fr', 'ar', 'de']))
for locale, resource in LOCALES.items():
    owner = json.loads(Path('/private/tmp/codex-apple-test-locks/macos-ui-session.lock/owner.json').read_text())
    assert owner['task'] == 'Pic2Link-mas-20260905'
    env = dict(os.environ, PIC2LINK_UI_TEST_LANGUAGE=resource,
               PIC2LINK_SCREENSHOT_OUTPUT=str(BASE / 'screenshots' / locale),
               PIC2LINK_SCREENSHOT_COPY=str(BASE / 'screenshot-copy' / locale / 'copy.json'))
    with (BASE / ('screenshot-' + locale + '-final.log')).open('w') as log:
        subprocess.run([str(APP / 'Contents/MacOS/Pic2Link'), '-storeScreenshots'], env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=45)
    print(locale + ': 3 pages × 2 appearances', flush=True)
