#!/usr/bin/env python3
"""Lint course lessons against the lesson skeleton (docs/LESSON-SKELETON.md).

Walks every docs/NN-*/ module folder. For each lesson file NN-*.md (anything
except 00-OVERVIEW.md) it enforces:

  * line 1 is "# <Title>"
  * line 3 is "**Lesson N of M: <Module>**", N == the file's number,
    M == the number of lesson files in the folder, same <Module> in every lesson
  * line 4 is "**Ticketing Project**"
  * every "> [!WARNING]" line is immediately followed by
    "> **Reality check (<slug>) —** <text>"
  * exactly one H2 "## K. See It: <what>"
  * at least one ```mermaid fence
  * H2s "Code: Python", "Code: Go", "Code: Rust", once each, in that order
  * no markdown links starting with ./ or ../ (links are repo-root-relative)
  * **Next:**, **Previous:** and **Module Overview:** links exist and resolve
    from the repo root (Module Overview -> this folder's 00-OVERVIEW.md)
  * a "Key Files Summary" table whose first-column paths exist

For each 00-OVERVIEW.md: if its lesson table marks any lesson "Done", the
folder must contain diagrams/hero.{mmd,svg,png,excalidraw}.

Headings, links and callouts inside fenced code blocks are ignored.

Usage:
  python3 scripts/lint_lessons.py [--root PATH]
  python3 scripts/lint_lessons.py --extract-mermaid DIR [--root PATH]

Exit status: 0 clean, 1 problems found (printed as path:line: message).
Stdlib only, so CI and the lab need nothing but python3.
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

MODULE_DIR_RE = re.compile(r"^\d{2}-.+$")
LESSON_FILE_RE = re.compile(r"^(\d{2})-.+\.md$")
OVERVIEW = "00-OVERVIEW.md"

TITLE_RE = re.compile(r"^# \S")
HEADER_RE = re.compile(r"^\*\*Lesson (\d+) of (\d+): (\S.*)\*\*$")
PROJECT_LINE = "**Ticketing Project**"
WARNING_RE = re.compile(r"^> \[!WARNING\]\s*$")
REALITY_RE = re.compile(r"^> \*\*Reality check \(([\w-]+)\) —\*\* \S")
SEE_IT_RE = re.compile(r"^## \d+\. See It: \S")
CODE_H2_RE = re.compile(r"^## (?:\d+\. )?Code: (Python|Go|Rust)\b")
H2_RE = re.compile(r"^## ")
KEY_FILES_RE = re.compile(r"^## (?:\d+\. )?Key Files Summary\s*$")
NAV_RE = re.compile(r"\*\*(Next|Previous|Module Overview):\*\*\s*(\[[^\]]*\]\(([^)\s]*)\))?")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)[^)]*\)")
REFDEF_RE = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(\S+)")
INLINE_CODE_RE = re.compile(r"`+[^`]*`+")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
TABLE_SEP_RE = re.compile(r"^\|?[\s:|-]+\|?$")
HERO_FILES = ("hero.mmd", "hero.svg", "hero.png", "hero.excalidraw")
CODE_ORDER = ("Python", "Go", "Rust")


@dataclass
class Fence:
    start: int  # 1-based line number of the opening fence
    lang: str
    body: list[str] = field(default_factory=list)


@dataclass
class Markdown:
    lines: list[str]
    prose: list[tuple[int, str]]  # (1-based line number, text) outside fences
    fences: list[Fence]
    unclosed: Fence | None


def parse(text: str) -> Markdown:
    """Split markdown into prose lines and fenced blocks (CommonMark fence rules)."""
    lines = text.splitlines()
    prose: list[tuple[int, str]] = []
    fences: list[Fence] = []
    current: tuple[str, int, Fence] | None = None
    for number, line in enumerate(lines, 1):
        match = FENCE_RE.match(line)
        if current is None:
            if match:
                marker, info = match.group(1), match.group(2).strip()
                if not (marker[0] == "`" and "`" in info):
                    fence = Fence(number, info.split()[0] if info else "")
                    fences.append(fence)
                    current = (marker[0], len(marker), fence)
                    continue
            prose.append((number, line))
            continue
        char, length, fence = current
        closes = match and match.group(1)[0] == char and len(match.group(1)) >= length
        if closes and not match.group(2).strip():
            current = None
            continue
        fence.body.append(line)
    return Markdown(lines, prose, fences, current[2] if current else None)


def split_row(row: str) -> list[str]:
    """Split a markdown table row into cells, ignoring pipes inside backticks."""
    cells, buf, in_code = [], [], False
    text = row.strip()
    text = text[1:] if text.startswith("|") else text
    text = text[:-1] if text.endswith("|") and not text.endswith("\\|") else text
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text) and text[i + 1] == "|":
            buf.append("|")
            i += 2
            continue
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
        i += 1
    cells.append("".join(buf).strip())
    return cells


def cell_paths(cell: str) -> list[str]:
    """Paths named in a Key Files cell: link targets, else code spans, else the text."""
    links = re.findall(r"\]\(([^)\s]+)\)", cell)
    if links:
        return links
    spans = re.findall(r"`([^`]+)`", cell)
    if spans:
        return spans
    return [cell.strip("*_ ")] if cell.strip("*_ ") else []


def path_exists(root: Path, target: str) -> bool:
    target = target.split("#", 1)[0]
    target = re.sub(r":\d+(-\d+)?$", "", target)
    if not target:
        return False
    if any(c in target for c in "*?["):
        return bool(glob.glob(str(root / target)))
    return (root / target).exists()


class Linter:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.problems: list[tuple[str, int, str]] = []
        self.lessons_checked = 0
        self.overviews_checked = 0

    def report(self, path: Path, line: int, message: str) -> None:
        self.problems.append((str(path.relative_to(self.root)), line, message))

    def module_dirs(self) -> list[Path]:
        docs = self.root / "docs"
        if not docs.is_dir():
            return []
        return sorted(p for p in docs.iterdir() if p.is_dir() and MODULE_DIR_RE.match(p.name))

    def run(self) -> int:
        for module in self.module_dirs():
            self.lint_module(module)
        for path, line, message in sorted(self.problems):
            print(f"{path}:{line}: {message}")
        print(
            f"lint_lessons: {len(self.module_dirs())} module(s), {self.lessons_checked} lesson(s), "
            f"{self.overviews_checked} overview(s) checked; {len(self.problems)} problem(s)",
            file=sys.stderr,
        )
        return 1 if self.problems else 0

    def lint_module(self, module: Path) -> None:
        overview = module / OVERVIEW
        if overview.is_file():
            self.lint_overview(overview)
        else:
            self.report(module, 0, f"module folder has no {OVERVIEW}")
        lessons = sorted(
            p
            for p in module.iterdir()
            if p.is_file() and LESSON_FILE_RE.match(p.name) and p.name != OVERVIEW
        )
        module_names: dict[str, Path] = {}
        for lesson in lessons:
            name = self.lint_lesson(lesson, total=len(lessons))
            if name:
                module_names.setdefault(name, lesson)
        if len(module_names) > 1:
            listed = ", ".join(f"'{n}' ({p.name})" for n, p in module_names.items())
            self.report(
                lessons[0], 3, f"lessons in one folder disagree on the module name: {listed}"
            )

    def lint_overview(self, path: Path) -> None:
        self.overviews_checked += 1
        md = parse(path.read_text(encoding="utf-8"))
        status_col: int | None = None
        done_line: int | None = None
        for number, line in md.prose:
            if not line.lstrip().startswith("|"):
                status_col = None
                continue
            cells = split_row(line)
            lowered = [c.strip("*_ `").lower() for c in cells]
            if "status" in lowered:
                status_col = lowered.index("status")
                continue
            if status_col is None or TABLE_SEP_RE.match(line.strip()):
                continue
            if status_col < len(cells) and cells[status_col].strip("*_ `").lower().startswith(
                "done"
            ):
                done_line = done_line or number
        if done_line is not None:
            missing = [f for f in HERO_FILES if not (path.parent / "diagrams" / f).is_file()]
            if missing:
                self.report(
                    path,
                    done_line,
                    "a lesson is marked Done, so diagrams/ needs the rendered hero: missing "
                    + ", ".join(missing),
                )

    def lint_lesson(self, path: Path, total: int) -> str | None:
        self.lessons_checked += 1
        md = parse(path.read_text(encoding="utf-8"))
        lines = md.lines
        number = int(LESSON_FILE_RE.match(path.name).group(1))  # type: ignore[union-attr]
        module_name: str | None = None

        def line_at(n: int) -> str:
            return lines[n - 1] if len(lines) >= n else ""

        if not TITLE_RE.match(line_at(1)):
            self.report(path, 1, 'line 1 must be the title: "# <Title>"')
        header = HEADER_RE.match(line_at(3))
        if not header:
            self.report(path, 3, f'line 3 must be "**Lesson {number} of {total}: <Module name>**"')
        else:
            n, m, module_name = int(header.group(1)), int(header.group(2)), header.group(3).strip()
            if n != number:
                self.report(path, 3, f"header says Lesson {n} but the file is lesson {number}")
            if m != total:
                self.report(
                    path, 3, f"header says of {m} but the folder has {total} lesson file(s)"
                )
        if line_at(4) != PROJECT_LINE:
            self.report(path, 4, f'line 4 must be "{PROJECT_LINE}"')

        if md.unclosed is not None:
            self.report(path, md.unclosed.start, "code fence is never closed")

        prose = md.prose
        prose_text = dict(prose)
        see_it: list[int] = []
        code_h2: list[tuple[int, str]] = []
        nav: dict[str, list[tuple[int, str | None]]] = {}
        for n, line in prose:
            if WARNING_RE.match(line):
                nxt = prose_text.get(n + 1, "")
                if not REALITY_RE.match(nxt):
                    self.report(
                        path,
                        n + 1,
                        '"> [!WARNING]" must be followed by '
                        '"> **Reality check (<slug>) —** <text>"',
                    )
            if SEE_IT_RE.match(line):
                see_it.append(n)
            code = CODE_H2_RE.match(line)
            if code:
                code_h2.append((n, code.group(1)))
            stripped = INLINE_CODE_RE.sub("", line)
            for target in LINK_RE.findall(stripped) + REFDEF_RE.findall(stripped):
                if target.startswith(("./", "../")):
                    self.report(
                        path, n, f"link '{target}' must be repo-root-relative (no ./ or ../)"
                    )
            for label, link, target in NAV_RE.findall(stripped):
                nav.setdefault(label, []).append((n, target if link else None))

        if len(see_it) != 1:
            where = see_it[1] if len(see_it) > 1 else 1
            self.report(
                path, where, f'need exactly one "## K. See It: ..." H2, found {len(see_it)}'
            )
        if not any(f.lang == "mermaid" for f in md.fences):
            self.report(path, 1, "need at least one ```mermaid diagram")
        self.check_code_order(path, code_h2)
        self.check_nav(path, nav, last_line=max(len(lines), 1))
        self.check_key_files(path, prose)
        return module_name

    def check_code_order(self, path: Path, code_h2: list[tuple[int, str]]) -> None:
        for lang in CODE_ORDER:
            hits = [n for n, found in code_h2 if found == lang]
            if len(hits) != 1:
                self.report(
                    path,
                    hits[1] if len(hits) > 1 else 1,
                    f'need exactly one "## K. Code: {lang}" H2, found {len(hits)}',
                )
        seen = [found for _, found in code_h2]
        if sorted(set(seen)) == sorted(CODE_ORDER) and len(seen) == 3 and tuple(seen) != CODE_ORDER:
            self.report(path, code_h2[0][0], "code sections must be ordered Python, Go, Rust")

    def check_nav(
        self, path: Path, nav: dict[str, list[tuple[int, str | None]]], last_line: int
    ) -> None:
        own_overview = (path.parent / OVERVIEW).relative_to(self.root).as_posix()
        for label in ("Next", "Previous", "Module Overview"):
            entries = nav.get(label)
            if not entries:
                self.report(path, last_line, f'missing "**{label}:** [..](docs/...)" link')
                continue
            for n, target in entries:
                if not target:
                    self.report(path, n, f'"**{label}:**" must be followed by a markdown link')
                    continue
                clean = target.split("#", 1)[0]
                if re.match(r"^[a-z]+:", clean) or clean.startswith("/"):
                    self.report(
                        path, n, f"{label} link '{target}' must be a repo-root-relative path"
                    )
                elif not (self.root / clean).exists():
                    self.report(
                        path,
                        n,
                        f"{label} link '{target}' does not exist (resolved from the repo root)",
                    )
                elif label == "Module Overview" and clean != own_overview:
                    self.report(
                        path, n, f"Module Overview must link to {own_overview}, not '{target}'"
                    )

    def check_key_files(self, path: Path, prose: list[tuple[int, str]]) -> None:
        start = next((i for i, (_, line) in enumerate(prose) if KEY_FILES_RE.match(line)), None)
        if start is None:
            self.report(
                path, 1, 'missing "## Key Files Summary" table (| File | Role | Language |)'
            )
            return
        rows: list[tuple[int, str]] = []
        for n, line in prose[start + 1 :]:
            if H2_RE.match(line):
                break
            if line.lstrip().startswith("|"):
                rows.append((n, line))
        data = [(n, r) for n, r in rows[1:] if not TABLE_SEP_RE.match(r.strip())]
        if not data:
            self.report(path, prose[start][0], "Key Files Summary table has no rows")
        for n, row in data:
            for target in cell_paths(split_row(row)[0]):
                if not path_exists(self.root, target):
                    self.report(
                        path, n, f"Key Files path '{target}' does not exist (from the repo root)"
                    )


SKIP_DIRS = {".git", "node_modules", ".venv", "target", ".claude", ".codex", "captures"}


def extract_mermaid(root: Path, out: Path) -> int:
    """Write every ```mermaid fence in the repo's markdown to OUT/<path>__L<line>.mmd."""
    out.mkdir(parents=True, exist_ok=True)
    count = 0
    for md_path in sorted(root.rglob("*.md")):
        rel = md_path.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        for fence in parse(md_path.read_text(encoding="utf-8")).fences:
            if fence.lang != "mermaid":
                continue
            name = re.sub(r"[^A-Za-z0-9._-]", "_", rel.as_posix()) + f"__L{fence.start}.mmd"
            (out / name).write_text("\n".join(fence.body) + "\n", encoding="utf-8")
            count += 1
    print(f"lint_lessons: extracted {count} mermaid diagram(s) to {out}", file=sys.stderr)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repo root (default: the checkout this script lives in)",
    )
    parser.add_argument(
        "--extract-mermaid",
        type=Path,
        metavar="DIR",
        help="write every ```mermaid fence to DIR/*.mmd and exit",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.extract_mermaid:
        return extract_mermaid(root, args.extract_mermaid)
    return Linter(root).run()


if __name__ == "__main__":
    sys.exit(main())
