#!/usr/bin/env python3
"""The changelog's tools (CHANGELOG.md follows Keep a Changelog).

    scripts/changelog.py check              is there something under [Unreleased]?
    scripts/changelog.py release 0.3.0      [Unreleased] becomes [0.3.0] - today, and a new empty one opens
    scripts/changelog.py notes 0.3.0        prints one version's notes (the release uses them)
    scripts/changelog.py latest             the newest numbered version

It only edits CHANGELOG.md; it never runs git.
"""
import datetime
import pathlib
import re
import sys

REPO = "https://github.com/frenkiieeee/MycSs"
FILE = pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md"
HEADING = re.compile(r"^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$")
LINK = re.compile(r"^\[[^\]]+\]: https?://")


def sections(lines):
    """(name, start, end) of every `## [x]` block; the links at the bottom are not part of one."""
    marks = [(i, HEADING.match(l).group(1)) for i, l in enumerate(lines) if HEADING.match(l)]
    result = []
    for n, (start, name) in enumerate(marks):
        end = marks[n + 1][0] if n + 1 < len(marks) else len(lines)
        while end > start and (not lines[end - 1].strip() or LINK.match(lines[end - 1])):
            end -= 1
        result.append((name, start, end))
    return result


def body(lines, name):
    for n, start, end in sections(lines):
        if n == name:
            return [l for l in lines[start + 1:end]]
    return None


def has_content(block):
    return any(l.lstrip().startswith(("-", "*")) for l in (block or []))


def versions(lines):
    return [n for n, _, _ in sections(lines) if n != "Unreleased"]


def links(lines, newest, previous):
    """The compare links at the bottom, rewritten for the versions there are now."""
    kept = [l for l in lines if not LINK.match(l)]
    while kept and not kept[-1].strip():
        kept.pop()
    names = versions(kept)
    out = [f"[Unreleased]: {REPO}/compare/v{names[0]}...HEAD"] if names else []
    for i, name in enumerate(names):
        out.append(f"[{name}]: {REPO}/compare/v{names[i + 1]}...v{name}" if i + 1 < len(names)
                   else f"[{name}]: {REPO}/releases/tag/v{name}")
    return kept + [""] + out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    lines = FILE.read_text().splitlines()

    if cmd == "check":
        ok = has_content(body(lines, "Unreleased"))
        print("[Unreleased] has notes" if ok else "[Unreleased] is empty")
        sys.exit(0 if ok else 1)

    if cmd == "latest":
        print(versions(lines)[0])
        return

    if cmd == "notes":
        block = body(lines, sys.argv[2])
        if block is None:
            sys.exit(f"no section for {sys.argv[2]}")
        print("\n".join(block).strip())
        return

    if cmd == "release":
        version = sys.argv[2]
        if not re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", version):
            sys.exit(f"'{version}' is not a semantic version")
        if body(lines, version) is not None:
            sys.exit(f"{version} is already in the changelog")
        if not has_content(body(lines, "Unreleased")):
            sys.exit("[Unreleased] is empty: nothing to release")
        day = sys.argv[3] if len(sys.argv) > 3 else datetime.date.today().isoformat()
        start = next(s for n, s, _ in sections(lines) if n == "Unreleased")
        lines[start:start + 1] = ["## [Unreleased]", "", f"## [{version}] - {day}"]
        FILE.write_text("\n".join(links(lines, version, None)) + "\n")
        print(f"CHANGELOG.md: [Unreleased] is now [{version}] - {day}")
        return

    sys.exit(__doc__)


main()
