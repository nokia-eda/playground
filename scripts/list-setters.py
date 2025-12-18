# Extract kpt setters names from the YAML files and present them in a Markdown table.
# Accepts a path to a directory containing YAML files. Files are searched recursively.

# /// script
# dependencies = [
#   "rich",
# ]
# ///

import os
import re

from rich.console import Console
from rich.table import Table


def find_yaml_files(root_dir):
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.endswith((".yaml", ".yml")):
                yield os.path.join(dirpath, filename)


def extract_setters_from_file(filepath):
    setters = []
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for line in lines:
        # https://regex101.com/r/D6vPEk/1
        match = re.search(r"^.*?([^#\s]+)\s+#\s*kpt-set:\s*\${([\w.-]+)}", line)
        if match:
            name = match.group(2)
            value = match.group(1).strip()
            if value.endswith(":"):
                # If the value ends with a colon, it's likely a key that was matched with a setter
                # like
                #
                # args: # kpt-set: ${CM_ARGS}
                #   - --v=2
                #
                # add a note to a user
                value = "Non scalar value, see the file for details."
            setters.append((name, value, ""))
    return setters


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Extract kpt setters and render as table."
    )
    parser.add_argument("directory", help="Directory to search for YAML files")
    parser.add_argument(
        "--markdown",
        action="store_true",
        help="Output as markdown table instead of rich table",
    )
    args = parser.parse_args()
    root_dir = args.directory
    rows = []
    seen = set()
    for yaml_file in find_yaml_files(root_dir):
        file_rows = []
        rel_file = os.path.relpath(yaml_file)
        # Drop the topmost directory from the relative path
        rel_parts = rel_file.split(os.sep, 1)
        if len(rel_parts) > 1:
            rel_file = rel_parts[1]
        for name, value, desc in extract_setters_from_file(yaml_file):
            if name not in seen:
                file_rows.append((name, value, desc))
                seen.add(name)
        if file_rows:
            rows.append({"file": rel_file, "setters": file_rows})
    if args.markdown:
        for group in rows:
            col_count = 2
            print("| Name | Value | ")
            print("|------|---------------|")
            print(f"| **{group['file']}** " + "|" * (col_count))
            for name, value, desc in group["setters"]:
                print(f"| `{name}` | {value} |")
            print()
    else:
        console = Console()
        for group in rows:
            table = Table(title=f"{group['file']}", show_lines=True)
            table.add_column("Name", style="cyan", no_wrap=True, min_width=20)
            table.add_column("Current Value", style="magenta", min_width=30)
            for name, value, desc in group["setters"]:
                table.add_row(name, value)
            console.print(table)


if __name__ == "__main__":
    main()
