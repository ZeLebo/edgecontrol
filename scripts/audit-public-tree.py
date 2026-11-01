#!/usr/bin/env python3
"""Reject private or generated files before a public commit or release."""
import argparse
import re
import subprocess
import sys

EXACT = {'.gitignore', 'README.md', 'CHANGELOG.md', 'Package.swift', 'Resources/Info.plist',
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--head', action='store_true', help='Inspect committed HEAD instead of index')
    mode.add_argument('--history', action='store_true', help='Inspect all reachable commits and tag identities')
    args = parser.parse_args()
    errors = []
    revisions = git('rev-list', '--all').decode().splitlines() if args.history else ['HEAD' if args.head else None]
    count = 0
    inspected = set()
    for revision in revisions:
        entries = (git('ls-tree', '-rz', '--full-tree', revision) if revision
                   else git('ls-files', '--stage', '-z')).split(b'\0')
        for entry in entries:
            if not entry:
                continue
            metadata, raw_path = entry.split(b'\t', 1)
            path = raw_path.decode('utf-8')
            file_mode, middle, last = metadata.split()
            object_id = last if revision else middle
            key = (path, file_mode, object_id)
            if key in inspected:
                continue
            inspected.add(key)
            if not allowed(path):
                errors.append(f'{path}: not in public source allowlist')
            if file_mode not in (b'100644', b'100755'):
                errors.append(f'{path}: non-regular file')
            if not revision and last != b'0':
                errors.append(f'{path}: unresolved index stage')
            if file_mode not in (b'100644', b'100755'):
                continue
            data = git('cat-file', 'blob', object_id.decode())
            for reason, pattern in RULES.items():
                if pattern.search(data):
                    errors.append(f'{path}: {reason}')
            count += 1
        if revision:
            for email in git('show', '-s', '--format=%ae%n%ce', revision).decode().splitlines():
                if not email.endswith('@users.noreply.github.com'):
                    errors.append(f'{revision}: author and committer must use a GitHub noreply address')
    if args.history:
        tags = git('for-each-ref', '--format=%(refname:short)%09%(taggeremail)', 'refs/tags').decode().splitlines()
        for tag in tags:
            name, email = tag.split('\t')
            if email and not email.strip('<>').endswith('@users.noreply.github.com'):
                errors.append(f'{name}: tagger must use a GitHub noreply address')
    if not count:
        errors.append('No public files selected')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    scope = f'{len(revisions)} commits, {count} source revisions' if args.history else f'{count} public source files'
    print(f'Audit passed: {scope}; no private paths, emails, keys, or tokens.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
