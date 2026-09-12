#!/usr/bin/env python3
"""Generate Pic2Link-only metadata and screenshot copy from local sources."""
from pathlib import Path
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LOCALES = dict(zip(
    ['en-US', 'zh-Hans', 'zh-Hant', 'ko', 'ja', 'ru', 'es-ES', 'pt-BR', 'th', 'hi', 'fr-FR', 'ar-SA', 'de-DE'],
    ['en', 'zh-Hans', 'zh-Hant', 'ko', 'ja', 'ru', 'es', 'pt', 'th', 'hi', 'fr', 'ar', 'de']))
COPY = json.loads((ROOT / 'fastlane/store-copy.json').read_text())
assert set(COPY) == set(LOCALES)
PRIVACY_URL = 'https://github.com/wallyvay/Pic2Link/blob/store-legal/PRIVACY.md'
SUPPORT_URL = 'https://github.com/wallyvay/Pic2Link/issues'

for locale, resource in LOCALES.items():
    subtitle, intro, details, keywords, caption = COPY[locale]
    assert len(subtitle) <= 30, (locale, 'subtitle', len(subtitle))
    assert len(keywords.encode('utf-8')) <= 100, (locale, 'keywords', len(keywords.encode('utf-8')))
    description = intro + '\n\n' + details
    assert len(description) <= 4000
    folder = ROOT / 'fastlane/metadata' / locale
    folder.mkdir(parents=True, exist_ok=True)
    fields = {'subtitle': subtitle, 'description': description, 'keywords': keywords,
              'privacy_url': PRIVACY_URL, 'support_url': SUPPORT_URL}
    if os.environ.get('PIC2LINK_STORE_NAME'):
        name = os.environ['PIC2LINK_STORE_NAME']
        assert name.startswith('Pic2Link') and len(name) <= 30
        fields['name'] = name
    for key, value in fields.items():
        (folder / (key + '.txt')).write_text(value + '\n')
    strings = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(ROOT / 'Pic2Link' / (resource + '.lproj') / 'Localizable.strings')]))
    screenshot = {'title1': subtitle, 'subtitle1': intro,
                  'title2': strings['caption.title'], 'subtitle2': strings['caption.description'],
                  'title3': strings['settings.profileList'], 'subtitle3': details.split('\n\n')[0],
                  'caption': caption}
    output = ROOT / 'dist/mas-20260905/screenshot-copy' / locale
    output.mkdir(parents=True, exist_ok=True)
    (output / 'copy.json').write_text(json.dumps(screenshot, ensure_ascii=False, indent=2))

(ROOT / 'fastlane/metadata/copyright.txt').write_text('2026 Li Wei\n')
print(f'Validated metadata and screenshot copy for {len(LOCALES)} locales. Store name: ' + ('set' if os.environ.get('PIC2LINK_STORE_NAME') else 'pending user selection'))
