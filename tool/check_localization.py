"""Check the mobile UI catalog without rewriting code or translating user data.
Run with Python 3. Checks literal tr()/trOrNull() keys and template placeholders.
"""
import ast
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / 'assets/l10n/messages.json').read_text(encoding='utf-8'))
slots = re.compile(r'\{\d+\}')
# Brand names, input examples, and format-only values intentionally stay literal.
literals = {'Home Serve', 'Home Serve AI', 'HOME SERVE', 'FPX', 'GrabPay',
            'Sarah Tan', 'name@example.com', 'user@example.com',
            '© OpenStreetMap contributors'}
errors = []
for source, translations in catalog.items():
    if not isinstance(translations, list) or len(translations) != 2:
        errors.append(f'Expected Chinese and Malay: {source!r}')
        continue
    for locale, translation in zip(('zh', 'ms'), translations):
        if not translation.strip() or sorted(slots.findall(source)) != sorted(slots.findall(translation)):
            errors.append(f'Invalid {locale} template: {source!r}')

calls = re.compile(r'''\btr(?:OrNull)?\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*[,)]''')
for path in (ROOT / 'lib').rglob('*.dart'):
    source = path.read_text(encoding='utf-8')
    for match in calls.finditer(source):
        key = ast.literal_eval(match.group(1).replace('\\$', '$'))
        if '$' in key:  # Interpolations are not literal keys; use explicit templates for copy.
            continue
        if key not in catalog and key not in literals and re.search('[A-Za-z]', key):
            line = source.count('\n', 0, match.start()) + 1
            errors.append(f'{path.relative_to(ROOT)}:{line}: Missing key {key!r}')
    # Catch fixed display text that accidentally bypasses translation entirely.
    # Interpolated/authored values are reviewed separately; numeric examples,
    # password masks, currency amounts and brands intentionally remain literal.
    display = re.compile(r'''\b(?:Text\(\s*|(?:hintText|labelText|tooltip):\s*)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''')
    for match in display.finditer(source):
        key = ast.literal_eval(match.group(1).replace('\\$', '$'))
        if '$' in key or key in literals or not re.search('[A-Za-z]', key):
            continue
        line = source.count('\n', 0, match.start()) + 1
        errors.append(f'{path.relative_to(ROOT)}:{line}: Untranslated display text {key!r}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f'Validated {len(catalog)} bilingual entries and literal UI translation keys.')
