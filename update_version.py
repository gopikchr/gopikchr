#!/usr/bin/env python3
"""
update_version.py - Update version information from upstream pikchr commit

Usage: ./update_version.py <commit-sha>

This script updates version/date information in both C and Go versions
to match a specific upstream pikchr commit.
"""

import sys
import subprocess
import re
from pathlib import Path
from datetime import datetime

def get_script_dir():
    """Get the directory containing this script."""
    return Path(__file__).parent.resolve()

def get_commit_info(pikchr_repo, commit_sha):
    """Get commit date and version from pikchr repository."""
    # Get commit date
    result = subprocess.run(
        ['git', 'show', '--format=%ci', commit_sha],
        cwd=pikchr_repo,
        capture_output=True,
        text=True,
        check=True
    )
    full_date = result.stdout.strip().split('\n')[0]

    # Parse date: "2025-03-05 00:29:51 +0000"
    parts = full_date.split()
    manifest_date = f"{parts[0]} {parts[1]}"
    manifest_isodate = parts[0].replace('-', '')

    # Get version from VERSION file if it exists
    try:
        result = subprocess.run(
            ['git', 'show', f'{commit_sha}:VERSION'],
            cwd=pikchr_repo,
            capture_output=True,
            text=True,
            check=True
        )
        release_version = result.stdout.strip()
    except subprocess.CalledProcessError:
        release_version = "1.0"

    return {
        'full_date': full_date,
        'manifest_date': manifest_date,
        'manifest_isodate': manifest_isodate,
        'release_version': release_version
    }

def update_c_version_h(script_dir, info):
    """Update c/VERSION.h file."""
    version_h_path = script_dir / 'c' / 'VERSION.h'
    content = f'''#define RELEASE_VERSION "{info['release_version']}"
#define MANIFEST_DATE "{info['manifest_date']}"
#define MANIFEST_ISODATE "{info['manifest_isodate']}"
'''
    version_h_path.write_text(content)
    print(f"✓ Updated {version_h_path}")

def update_go_pikchr_y(script_dir, info):
    """Update internal/pikchr.y constants."""
    pikchr_y_path = script_dir / 'internal' / 'pikchr.y'
    content = pikchr_y_path.read_text()

    # Update the three version constants
    content = re.sub(
        r'ReleaseVersion\s*=\s*"[^"]*"',
        f'ReleaseVersion   = "{info["release_version"]}"',
        content
    )
    content = re.sub(
        r'ManifestDate\s*=\s*"[^"]*"',
        f'ManifestDate     = "{info["manifest_date"]}"',
        content
    )
    content = re.sub(
        r'ManifestISODate\s*=\s*"[^"]*"',
        f'ManifestISODate  = "{info["manifest_isodate"]}"',
        content
    )

    pikchr_y_path.write_text(content)
    print(f"✓ Updated {pikchr_y_path}")

def main():
    if len(sys.argv) != 2:
        print(__doc__)
        print("Example: ./update_version.py 9c5ced3599")
        sys.exit(1)

    commit_sha = sys.argv[1]
    script_dir = get_script_dir()
    pikchr_repo = script_dir.parent / 'pikchr'

    # Check if pikchr repo exists
    if not pikchr_repo.is_dir():
        print(f"Error: pikchr repository not found at {pikchr_repo}")
        print("Expected directory structure:")
        print("  ~/gh/p_gopikchr/pikchr    (upstream repo)")
        print("  ~/gh/p_gopikchr/gopikchr  (this repo)")
        sys.exit(1)

    # Check if commit exists
    try:
        subprocess.run(
            ['git', 'cat-file', '-e', f'{commit_sha}^{{commit}}'],
            cwd=pikchr_repo,
            capture_output=True,
            check=True
        )
    except subprocess.CalledProcessError:
        print(f"Error: Commit {commit_sha} not found in pikchr repository")
        sys.exit(1)

    # Get commit information
    print(f"Getting commit date from pikchr repository...")
    info = get_commit_info(pikchr_repo, commit_sha)

    print()
    print(f"Commit:  {commit_sha}")
    print(f"Date:    {info['full_date']}")
    print(f"Version: {info['release_version']}")
    print()

    # Update files
    update_c_version_h(script_dir, info)
    update_go_pikchr_y(script_dir, info)

    print()
    print("✓ Version information updated successfully!")
    print()
    print("Next steps:")
    print("  1. Regenerate internal/pikchr.go: cd internal && ../../golemon/bin/golemon pikchr.y")
    print("  2. Run tests: ./dotest.sh")
    print("  3. Commit changes")

if __name__ == '__main__':
    main()
