#!/usr/bin/env python3
"""Reject broken local website assets and fragment links before deployment."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'site').resolve()

class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.refs = []
        self.errors = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a:
            if a['id'] in self.ids:
                self.errors.append('duplicate id: ' + a['id'])
            self.ids.add(a['id'])
        for key in ('src', 'href', 'poster'):
            if a.get(key):
                self.refs.append(a[key])
        if tag == 'img' and 'alt' not in a:
            self.errors.append('image missing alt attribute: ' + a.get('src', '?'))

p = References()
p.feed((root / 'index.html').read_text())
errors = p.errors
count = 0
for ref in p.refs:
    u = urlsplit(ref)
    if u.scheme or u.netloc:
        continue
    if not u.path:
        if u.fragment and unquote(u.fragment) not in p.ids:
            errors.append('missing fragment: ' + ref)
        continue
    target = (root / unquote(u.path)).resolve()
    if not target.is_relative_to(root) or not target.is_file() or target.stat().st_size == 0:
        errors.append('missing or empty asset: ' + ref)
    count += 1
for css in root.glob('*.css'):
    for ref in re.findall(r'url\([\"\']?([^\"\')]+)', css.read_text()):
        if not urlsplit(ref).scheme and not ref.startswith('#'):
            if not (root / unquote(ref)).is_file():
                errors.append('missing CSS asset: ' + ref)
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Website verified: {count} local asset references, {len(p.ids)} fragment targets; no broken assets or duplicate IDs.')
