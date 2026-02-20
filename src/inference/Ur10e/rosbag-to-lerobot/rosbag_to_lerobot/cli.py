"""CLI entry point for rosbag-to-lerobot conversion.

Usage
-----
Convert rosbags from blob storage::

    rosbag-to-lerobot convert --config config.yaml

Convert a local rosbag::

    rosbag-to-lerobot convert --local-bag /path/to/bag --no-upload

List available rosbags in blob storage::

    rosbag-to-lerobot list --config config.yaml

Inspect a local rosbag::

    rosbag-to-lerobot inspect /path/to/bag
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .blob_storage import BlobStorageClient
from .config import load_config
from .converter import run_conversion
from .rosbag_reader import inspect_bag

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------


def _cmd_convert(args: argparse.Namespace) -> int:
    """Execute the convert subcommand."""
    cfg = load_config(args.config)

    # Apply CLI overrides
    if args.blob_prefix:
        cfg.blob_storage.rosbag_prefix = args.blob_prefix
    if args.output_prefix:
        cfg.blob_storage.lerobot_prefix = args.output_prefix
    if args.task:
        cfg.dataset.task_description = args.task
    if args.fps:
        cfg.dataset.fps = args.fps
    if args.vcodec:
        cfg.dataset.vcodec = args.vcodec
    if args.repo_id:
        cfg.dataset.repo_id = args.repo_id
    if args.no_sign_flip:
        cfg.conventions.apply_joint_sign = False
    if args.split_episodes:
        cfg.processing.split_episodes = True

    local_bags = [Path(p) for p in args.local_bag] if args.local_bag else None
    output_dir = Path(args.output_dir)

    logger.info("Configuration: %s", cfg)
    run_conversion(cfg, output_dir, local_bags=local_bags, skip_upload=args.no_upload)
    return 0


def _cmd_list(args: argparse.Namespace) -> int:
    """Execute the list subcommand."""
    cfg = load_config(args.config)
    prefix = args.prefix or cfg.blob_storage.rosbag_prefix

    client = BlobStorageClient(
        account_url=cfg.blob_storage.account_url,
        container_name=cfg.blob_storage.container,
    )
    bags = client.discover_bags(prefix)

    print(f"\nDiscovered {len(bags)} bag(s) under '{prefix}':\n")
    for i, bag in enumerate(bags, 1):
        print(f"  {i}. {bag}")
    print()
    return 0


def _cmd_inspect(args: argparse.Namespace) -> int:
    """Execute the inspect subcommand."""
    bag_path = Path(args.bag_path)
    if not bag_path.exists():
        logger.error("Bag path does not exist: %s", bag_path)
        return 1

    info = inspect_bag(bag_path, ros_distro=args.distro)

    print(f"\nBag: {bag_path}")
    print(f"Duration: {info['duration_s']:.1f} s")
    print(f"\nTopics ({len(info['topics'])}):")
    for topic in info["topics"]:
        print(f"  {topic['name']:<40} {topic['type']:<40} {topic['count']:>8} msgs")
    print()
    return 0


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    """Build the top-level argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        description="Convert ROS bag recordings to LeRobot v3 datasets",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # -- convert --------------------------------------------------------
    p_convert = subparsers.add_parser("convert", help="Convert rosbags to LeRobot dataset")
    p_convert.add_argument("--config", default="config.yaml", help="Path to config YAML")
    p_convert.add_argument("--blob-prefix", default=None, help="Override blob rosbag prefix")
    p_convert.add_argument("--output-dir", default="./output", help="Local output directory")
    p_convert.add_argument("--output-prefix", default=None, help="Override blob upload prefix")
    p_convert.add_argument("--task", default=None, help="Override task description")
    p_convert.add_argument("--fps", type=int, default=None, help="Override target FPS")
    p_convert.add_argument(
        "--vcodec",
        choices=["libsvtav1", "h264", "hevc"],
        default=None,
        help="Video codec for encoding",
    )
    p_convert.add_argument(
        "--no-upload", action="store_true", help="Skip uploading to blob storage"
    )
    p_convert.add_argument(
        "--local-bag", nargs="+", default=None, help="Use local bag path(s) instead of blob"
    )
    p_convert.add_argument("--repo-id", default=None, help="Override dataset repo ID")
    p_convert.add_argument(
        "--no-sign-flip", action="store_true", help="Disable joint sign convention flip"
    )
    p_convert.add_argument(
        "--split-episodes", action="store_true", help="Detect episode boundaries automatically"
    )

    # -- list -----------------------------------------------------------
    p_list = subparsers.add_parser("list", help="List available rosbags in blob storage")
    p_list.add_argument("--config", default="config.yaml", help="Path to config YAML")
    p_list.add_argument("--prefix", default=None, help="Blob prefix to list")

    # -- inspect --------------------------------------------------------
    p_inspect = subparsers.add_parser("inspect", help="Inspect a local rosbag")
    p_inspect.add_argument("bag_path", help="Path to the rosbag directory or file")
    p_inspect.add_argument(
        "--distro", default="ROS2_HUMBLE", help="ROS distribution (default: ROS2_HUMBLE)"
    )

    return parser


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    """CLI entry point."""
    parser = _build_parser()
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    commands: dict[str, callable] = {
        "convert": _cmd_convert,
        "list": _cmd_list,
        "inspect": _cmd_inspect,
    }
    return commands[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
