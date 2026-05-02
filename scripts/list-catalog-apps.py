#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "sh",
#   "tabulate",
#   "rich",
# ]
# ///

import argparse
from pathlib import Path
from rich.console import Console
from rich.table import Table
import sh

c=Console()

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--catalog", type=Path, help="Path to the catalog")
    return parser.parse_args()

def get_tags_from_catalog(catalog: Path) -> list[str]:
    out = sh.git("-C", catalog, "--no-pager", "tag", "--list")  # Get the tags
    all_tags = [line.strip() for line in out.splitlines()]      # Clean up the output
    tags = [tag for tag in all_tags if tag.startswith("apps/")] # Filter out the tags that only start with "apps/"
    return tags

def tabulate_app_versions(catalog_tags: list[str]) -> None:
    apps = {}
    for catalog_tag in catalog_tags:
        tag = catalog_tag.split("/")
        name = tag[1]
        version = tag [2]

        if name not in apps:
            apps[name] = []
        apps[name].append(version)

    table = Table(title="App Versions")
    table.add_column("Name", justify="right", style="magenta")
    table.add_column("Versions", justify="left")

    for name, versions in apps.items():
        table.add_row(name, ", ".join(sorted(versions, reverse=True)))

    c.print(table)

def main():
    args = parse_args()
    catalog = args.catalog

    if not catalog.exists() or not catalog.is_dir():
        c.print(f"[red]Catalog:'{catalog}' does not exist or is not a directory[/red]")
        return 1

    tags = get_tags_from_catalog(catalog)
    tabulate_app_versions(tags)

if __name__ == "__main__":
    main()