"""Download rosbags from Azure Blob Storage and optionally convert to LeRobot datasets.

Standalone script for interactive or targeted bag download and conversion.
Supports listing available bags, selecting by name or interactively, and
converting one or all bags in a single run.

Usage
-----
List available bags::

    python download_and_convert.py --list

Download and convert a specific bag::

    python download_and_convert.py --bag recording_xxx

Download and convert ALL bags::

    python download_and_convert.py --all

Download only (skip conversion)::

    python download_and_convert.py --bag recording_xxx --skip-convert

Interactive selection (prompts you to pick)::

    python download_and_convert.py

Custom output paths::

    python download_and_convert.py --bag recording_xxx \
        --output-bags ./my_bags --output-dataset ./my_datasets
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from rosbag_to_lerobot.blob_storage import BlobStorageClient
from rosbag_to_lerobot.config import load_config
from rosbag_to_lerobot.converter import run_conversion

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# Suppress noisy Azure HTTP logging.
for _azlog in (
    "azure.core.pipeline.policies.http_logging_policy",
    "azure.identity",
    "azure.core",
):
    logging.getLogger(_azlog).setLevel(logging.WARNING)

# Defaults relative to this script's directory.
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_BAGS_DIR = SCRIPT_DIR / "local_bags"
DEFAULT_DATASET_DIR = SCRIPT_DIR / "local_datasets"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _extract_bag_name(prefix: str) -> str:
    """Extract a short bag name from a blob prefix.

    Example: 'houston_recordings/recording_xxx/' -> 'recording_xxx'
    """
    return prefix.rstrip("/").rsplit("/", 1)[-1]


def _discover_and_print(client: BlobStorageClient, rosbag_prefix: str) -> list[str]:
    """Discover available bags and print a numbered listing.

    Returns:
        Bag prefixes discovered in blob storage.
    """
    bags = client.discover_bags(rosbag_prefix)
    if not bags:
        print(f"\nNo bags found under prefix '{rosbag_prefix}'")
        return []

    print(f"\nFound {len(bags)} bag(s) under '{rosbag_prefix}':\n")
    for i, bag in enumerate(bags, 1):
        name = _extract_bag_name(bag)
        print(f"  {i:3d}. {name:<40s}  ({bag})")
    print()
    return bags


def _find_matching_bags(bags: list[str], query: str) -> list[str]:
    """Return bags whose name matches *query* exactly or as a substring."""
    # Exact match first.
    for bag in bags:
        if _extract_bag_name(bag) == query or bag == query:
            return [bag]
    # Substring / partial match.
    return [b for b in bags if query.lower() in _extract_bag_name(b).lower()]


def _interactive_pick(bags: list[str]) -> str | None:
    """Show a numbered list and let the user pick a bag interactively.

    Also accepts partial name input for convenience.
    """
    while True:
        try:
            choice = input("Select a bag number (or 'q' to quit): ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return None

        if choice.lower() in ("q", "quit", "exit", ""):
            return None

        try:
            idx = int(choice) - 1
            if 0 <= idx < len(bags):
                return bags[idx]
            print(f"  Please enter a number between 1 and {len(bags)}")
        except ValueError:
            # Try matching by name substring.
            matches = _find_matching_bags(bags, choice)
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                print(f"  Ambiguous: {len(matches)} bags match '{choice}'. Be more specific.")
            else:
                print(f"  No bag matches '{choice}'. Enter a number or partial name.")


# ---------------------------------------------------------------------------
# Download & convert
# ---------------------------------------------------------------------------


def _download_one(
    client: BlobStorageClient,
    bag_prefix: str,
    bags_dir: Path,
) -> Path:
    """Download a rosbag to *bags_dir/<bag_name>/*.

    Skips the download when the directory already exists and contains files.

    Returns:
        Local path where the bag was saved.
    """
    bag_name = _extract_bag_name(bag_prefix)
    local_bag_dir = bags_dir / bag_name

    # Skip if already downloaded.
    if local_bag_dir.exists() and any(local_bag_dir.rglob("*")):
        file_count = sum(1 for f in local_bag_dir.rglob("*") if f.is_file())
        logger.info(
            "Bag '%s' already downloaded (%d files). Skipping download.",
            bag_name,
            file_count,
        )
        print(f"  '{bag_name}' already cached ({file_count} files)")
        return local_bag_dir

    local_bag_dir.mkdir(parents=True, exist_ok=True)

    print(f"  Downloading '{bag_name}' -> {local_bag_dir} ...")
    t0 = time.time()
    client.download_directory(bag_prefix, local_bag_dir)
    elapsed = time.time() - t0

    file_count = sum(1 for f in local_bag_dir.rglob("*") if f.is_file())
    total_size = sum(f.stat().st_size for f in local_bag_dir.rglob("*") if f.is_file())
    size_mb = total_size / (1024 * 1024)

    print(f"  Downloaded {file_count} file(s), {size_mb:.1f} MB in {elapsed:.0f} s")
    return local_bag_dir


def _convert_one(
    cfg,
    local_bag_dir: Path,
    dataset_dir: Path,
) -> Path:
    """Convert a single downloaded bag into a LeRobot dataset.

    Each bag gets its own sub-directory under *dataset_dir* so multiple
    conversions coexist without overwriting each other.

    Returns:
        Path to the output dataset directory.
    """
    bag_name = local_bag_dir.name
    output_path = dataset_dir / bag_name

    print(f"  Converting '{bag_name}' -> {output_path} ...")
    t0 = time.time()

    run_conversion(
        cfg,
        output_dir=output_path,
        local_bags=[local_bag_dir],
        skip_upload=True,
    )

    elapsed = time.time() - t0
    print(f"  Conversion completed in {elapsed:.0f} s")
    return output_path


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------


def _print_summary(
    selected: list[str],
    downloaded: list[Path],
    converted: list[Path],
    failed: list[str],
    bags_dir: Path,
    dataset_dir: Path,
    skip_convert: bool,
) -> None:
    """Print a final summary of all operations."""
    print("\n" + "=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    print(f"  Selected:   {len(selected)}")
    print(f"  Downloaded: {len(downloaded)}  -> {bags_dir}")
    if not skip_convert:
        print(f"  Converted:  {len(converted)}  -> {dataset_dir}")
    if failed:
        print(f"  Failed:     {len(failed)}  ({', '.join(failed)})")

    # Show dataset contents for single-bag runs.
    if len(converted) == 1 and converted[0].exists():
        ds = converted[0]
        print(f"\n  Dataset contents ({ds.name}):")
        for child in sorted(ds.iterdir()):
            if child.is_dir():
                fc = sum(1 for f in child.rglob("*") if f.is_file())
                print(f"    {child.name}/  ({fc} files)")
            else:
                size_kb = child.stat().st_size / 1024
                print(f"    {child.name}  ({size_kb:.1f} KB)")

    print("=" * 60 + "\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(
        description="Download rosbags from Azure Blob Storage and convert to LeRobot datasets.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python download_and_convert.py --list\n"
            "  python download_and_convert.py --bag recording_xxx\n"
            "  python download_and_convert.py --all\n"
            "  python download_and_convert.py --all --skip-convert\n"
            "  python download_and_convert.py  # interactive pick\n"
        ),
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=SCRIPT_DIR / "config.yaml",
        help="Path to config.yaml (default: config.yaml in script directory)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        dest="list_only",
        help="List available bags and exit",
    )
    parser.add_argument(
        "--bag",
        type=str,
        default=None,
        help="Bag name to download (exact or partial match)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="download_all",
        help="Download and convert ALL available bags",
    )
    parser.add_argument(
        "--output-bags",
        type=Path,
        default=DEFAULT_BAGS_DIR,
        help=f"Directory for downloaded rosbags (default: {DEFAULT_BAGS_DIR.relative_to(SCRIPT_DIR)})",
    )
    parser.add_argument(
        "--output-dataset",
        type=Path,
        default=DEFAULT_DATASET_DIR,
        help=f"Directory for converted datasets (default: {DEFAULT_DATASET_DIR.relative_to(SCRIPT_DIR)})",
    )
    parser.add_argument(
        "--skip-convert",
        action="store_true",
        help="Download only, skip LeRobot conversion",
    )
    return parser


def main() -> int:
    """CLI entry point."""
    parser = _build_parser()
    args = parser.parse_args()

    # Load configuration.
    cfg = load_config(args.config)

    bags_dir = args.output_bags.resolve()
    dataset_dir = args.output_dataset.resolve()

    # ---- Connect to blob storage ----
    print(f"Connecting to {cfg.blob_storage.account_url} ...")
    try:
        client = BlobStorageClient(
            account_url=cfg.blob_storage.account_url,
            container_name=cfg.blob_storage.container,
        )
    except Exception as exc:
        logger.error(
            "Failed to connect to blob storage at %s: %s",
            cfg.blob_storage.account_url,
            exc,
        )
        logger.error(
            "Ensure you are authenticated (az login) and the storage account URL is correct."
        )
        return 1

    # ---- Discover available bags ----
    try:
        bags = _discover_and_print(client, cfg.blob_storage.rosbag_prefix)
    except Exception as exc:
        logger.error("Failed to list bags: %s", exc)
        return 1

    if args.list_only:
        return 0

    if not bags:
        logger.error("No bags available to download.")
        return 1

    # ---- Select which bags to process ----
    selected: list[str] = []

    if args.download_all:
        selected = list(bags)
        print(f"Selected ALL {len(selected)} bag(s)")
    elif args.bag:
        matches = _find_matching_bags(bags, args.bag)
        if not matches:
            logger.error(
                "No bag matching '%s'. Use --list to see available bags.", args.bag
            )
            return 1
        if len(matches) > 1:
            print(f"\nMultiple bags match '{args.bag}':\n")
            for m in matches:
                print(f"  - {_extract_bag_name(m)}")
            print("\nPlease be more specific.")
            return 1
        selected = matches
        print(f"Selected: {_extract_bag_name(selected[0])}")
    else:
        # Interactive mode.
        pick = _interactive_pick(bags)
        if pick is None:
            print("Cancelled.")
            return 0
        selected = [pick]
        print(f"Selected: {_extract_bag_name(selected[0])}")

    # ---- Process each selected bag ----
    downloaded: list[Path] = []
    converted: list[Path] = []
    failed: list[str] = []

    for i, bag_prefix in enumerate(selected, 1):
        name = _extract_bag_name(bag_prefix)
        print(f"\n[{i}/{len(selected)}] {name}")
        t0 = time.time()

        # Download.
        try:
            local_path = _download_one(client, bag_prefix, bags_dir)
            downloaded.append(local_path)
        except Exception:
            logger.exception("Failed to download '%s'", name)
            failed.append(name)
            continue

        # Convert (unless skipped).
        if not args.skip_convert:
            try:
                ds_path = _convert_one(cfg, local_path, dataset_dir)
                converted.append(ds_path)
            except Exception:
                logger.exception("Failed to convert '%s'", name)
                failed.append(name)
                continue

        elapsed = time.time() - t0
        logger.info("[%d/%d] Done '%s' in %.0f s", i, len(selected), name, elapsed)

    # ---- Summary ----
    _print_summary(selected, downloaded, converted, failed, bags_dir, dataset_dir, args.skip_convert)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
