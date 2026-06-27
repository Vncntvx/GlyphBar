#!/usr/bin/env python3
"""Register a new .swift source file in GlyphBar.xcodeproj/project.pbxproj.

The project uses explicit file references (no folder sync), so every new Swift
file must be added in four places: PBXBuildFile, PBXFileReference, its Xcode
group's children, and the target's Sources build phase.

Usage:
    python3 script/add_swift_file.py <new_disk_path> <sibling_disk_path>

- <new_disk_path>     : on-disk path of the new file, e.g.
                        GlyphBar/App/Settings/GeneralSettingsView.swift
- <sibling_disk_path> : an EXISTING source file in the SAME Xcode group as the
                        new file, e.g. GlyphBar/App/Settings/SettingsRootView.swift

The script locates the sibling's group and Sources phase from the sibling, so it
never creates new groups. Paths may be given with or without the leading
"GlyphBar/" / "Tests/" / "GlyphBarWidgets/" prefix. Run
`./script/build_and_run.sh --build` afterwards to verify.
"""
import re
import sys
import uuid
from pathlib import Path

PB = Path("GlyphBar.xcodeproj/project.pbxproj")


def pbx_path(disk_path: str) -> str:
    """Convert a disk path to the pbxproj group-relative path."""
    p = disk_path.strip()
    for prefix in ("GlyphBar/", "Tests/", "GlyphBarWidgets/"):
        if p.startswith(prefix):
            return p[len(prefix):]
    return p


def find(pattern: str, text: str, what: str) -> str:
    m = re.search(pattern, text)
    if not m:
        sys.exit(f"add_swift_file: could not find {what}")
    return m.group(1)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: add_swift_file.py <new_disk_path> <sibling_disk_path>")
    new_disk, sib_disk = sys.argv[1], sys.argv[2]
    new_path = pbx_path(new_disk)
    sib_path = pbx_path(sib_disk)

    if not Path(new_disk).exists() and not Path("GlyphBar/" + new_path).exists():
        sys.exit(f"add_swift_file: new file does not exist on disk: {new_disk}")

    text = PB.read_text()

    sib_ref = find(
        rf"([A-F0-9]{{24}}) /\* {re.escape(sib_path)} \*/ = \{{isa = PBXFileReference",
        text, "sibling fileRef",
    )
    sib_bld = find(
        rf"([A-F0-9]{{24}}) /\* {re.escape(sib_path)} in Sources \*/ = \{{isa = PBXBuildFile; fileRef = {sib_ref} ",
        text, "sibling buildFile",
    )

    new_ref = "A" + uuid.uuid4().hex[:23].upper()
    new_bld = "B" + uuid.uuid4().hex[:23].upper()

    bld_line = (
        f"\t\t{new_bld} /* {new_path} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {new_ref} /* {new_path} */; }};\n"
    )
    text, n1 = re.subn(r"(/\* End PBXBuildFile section \*/\n)", bld_line + r"\1", text, count=1)
    if n1 != 1:
        sys.exit("add_swift_file: PBXBuildFile section marker not found")

    ref_line = (
        f"\t\t{new_ref} /* {new_path} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {new_path}; "
        f'sourceTree = "<group>"; }};\n'
    )
    text, n2 = re.subn(r"(/\* End PBXFileReference section \*/\n)", ref_line + r"\1", text, count=1)
    if n2 != 1:
        sys.exit("add_swift_file: PBXFileReference section marker not found")

    def insert_after(match: "re.Match[str]") -> str:
        indent = match.group(1)
        return match.group(0) + f"{indent}{new_ref} /* {new_path} */,\n"

    child_pat = rf"(\t*){sib_ref} /\* {re.escape(sib_path)} \*/,\n"
    text, n3 = re.subn(child_pat, insert_after, text, count=1)
    if n3 != 1:
        sys.exit("add_swift_file: sibling not found in any group children")

    def insert_after_src(match: "re.Match[str]") -> str:
        indent = match.group(1)
        return match.group(0) + f"{indent}{new_bld} /* {new_path} in Sources */,\n"

    src_pat = rf"(\t*){sib_bld} /\* {re.escape(sib_path)} in Sources \*/,\n"
    text, n4 = re.subn(src_pat, insert_after_src, text, count=1)
    if n4 != 1:
        sys.exit("add_swift_file: sibling not found in Sources phase")

    PB.write_text(text)
    print(f"added {new_path}  (fileRef={new_ref}, buildFile={new_bld})")


if __name__ == "__main__":
    main()
