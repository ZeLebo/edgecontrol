#!/usr/bin/env python3
"""Reject private or generated files before a public commit or release."""
import argparse
import re
import subprocess
import sys

EXACT = {'.gitignore', 'README.md', 'Package.swift', 'Resources/Info.plist',
         'Resources/EdgeControlIcon.png', 'scripts/build-app.sh', 'scripts/build-icon.swift',
         'scripts/audit-public-tree.py', 'scripts/release.sh'}
RULES = {
    'machine-specific path': re.compile(rb'\x2f(?:Users|home|Applications|private|var|System|Library)\x2f', re.I),
    'email address': re.compile(rb'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', re.I),
    'access token': re.compile(rb'(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
}

def git(*args):
    return subprocess.check_output(['git', *args])

def allowed(path):
    if path in EXACT:
        return True
    return bool(re.fullmatch(r'(?:Sources/EdgeControl|Tests/EdgeControlTests)/[^/]+\.swift', path))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', action='store_true', help='Inspect committed HEAD instead of index')
    args = parser.parse_args()
    errors = []
    if args.head:
        entries = git('ls-tree', '-rz', '--full-tree', 'HEAD').split(b'\0')
    else:
        entries = git('ls-files', '--stage', '-z').split(b'\0')
    count = 0
    for entry in entries:
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        path = raw_path.decode('utf-8')
        mode, _, stage = metadata.split()
        if not allowed(path):
            errors.append(f'{path}: not in public source allowlist')
        if mode not in (b'100644', b'100755'):
            errors.append(f'{path}: non-regular file')
        if not args.head and stage != b'0':
            errors.append(f'{path}: unresolved index stage')
        data = git('show', f'HEAD:{path}' if args.head else f':{path}')
        for reason, pattern in RULES.items():
            if pattern.search(data):
                errors.append(f'{path}: {reason}')
        count += 1
    if args.head:
        for email in git('show', '-s', '--format=%ae%n%ce', 'HEAD').decode().splitlines():
            if not email.endswith('@users.noreply.github.com'):
                errors.append('HEAD: author and committer must use a GitHub noreply address')
    if not count:
        errors.append('No public files selected')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Audit passed: {count} public source files; no private paths, emails, keys, or tokens.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
