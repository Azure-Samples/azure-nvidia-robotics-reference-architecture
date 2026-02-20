"""Tests for temporal synchronization and episode detection."""

from __future__ import annotations

import numpy as np

from rosbag_to_lerobot.rosbag_reader import ImageSample, JointSample
from rosbag_to_lerobot.sync import detect_episodes, split_by_episodes, synchronize


def _make_joint_samples(n: int, rate_hz: float, start_ns: int = 0) -> list[JointSample]:
    interval_ns = int(1e9 / rate_hz)
    return [
        JointSample(
            timestamp_ns=start_ns + i * interval_ns,
            names=[f"j{j}" for j in range(6)],
            position=np.random.default_rng(i).random(6),
            velocity=None,
        )
        for i in range(n)
    ]


def _make_image_samples(n: int, rate_hz: float, start_ns: int = 0) -> list[ImageSample]:
    interval_ns = int(1e9 / rate_hz)
    return [
        ImageSample(
            timestamp_ns=start_ns + i * interval_ns,
            image=np.zeros((480, 848, 3), dtype=np.uint8),
            width=848,
            height=480,
        )
        for i in range(n)
    ]


class TestSynchronize:
    def test_basic_sync_30hz(self):
        joints = _make_joint_samples(5000, 500.0)  # 10s at 500 Hz
        images = _make_image_samples(300, 30.0)  # 10s at 30 Hz
        result = synchronize(joints, images, fps=30)
        assert result.frame_count > 0
        # Should be roughly 10s * 30fps = ~300 frames
        assert 250 < result.frame_count < 310

    def test_frame_count_matches_duration(self):
        joints = _make_joint_samples(2500, 500.0)  # 5s at 500 Hz
        images = _make_image_samples(150, 30.0)  # 5s at 30 Hz
        result = synchronize(joints, images, fps=30)
        expected = int(result.duration_s * 30)
        assert abs(result.frame_count - expected) <= 2

    def test_offset_tracking(self):
        joints = _make_joint_samples(5000, 500.0)
        images = _make_image_samples(300, 30.0)
        result = synchronize(joints, images, fps=30)
        # Joint offset should be very small (500 Hz data)
        assert result.max_joint_offset_ms < 2.0  # < 1/500 s = 2 ms
        # Image offset should be moderate (30 Hz data)
        assert result.max_image_offset_ms < 20.0  # < 1/30 s ~ 33 ms

    def test_drops_frames_beyond_max_offset(self):
        joints = _make_joint_samples(100, 500.0)
        images = _make_image_samples(5, 30.0)  # Very sparse images
        result = synchronize(joints, images, fps=30, max_offset_ms=5.0)
        # Most frames should be dropped with tight offset
        assert result.frame_count < 10

    def test_empty_result_when_no_overlap(self):
        joints = _make_joint_samples(100, 500.0, start_ns=0)
        images = _make_image_samples(100, 30.0, start_ns=int(10e9))  # 10s later
        # Should raise or return empty (arrays don't overlap)
        # Joint samples end before images start
        result = synchronize(joints, images, fps=30)
        assert result.frame_count == 0


class TestDetectEpisodes:
    def test_no_gaps(self):
        joints = _make_joint_samples(1000, 500.0)
        boundaries = detect_episodes(joints, gap_threshold_s=2.0)
        assert len(boundaries) == 1
        assert boundaries[0] == (0, 999)

    def test_single_gap(self):
        part1 = _make_joint_samples(500, 500.0, start_ns=0)
        part2 = _make_joint_samples(500, 500.0, start_ns=int(5e9))  # 5s gap
        joints = part1 + part2
        boundaries = detect_episodes(joints, gap_threshold_s=2.0)
        assert len(boundaries) == 2

    def test_multiple_gaps(self):
        parts = []
        for seg in range(4):
            parts.extend(_make_joint_samples(100, 500.0, start_ns=int(seg * 5e9)))
        boundaries = detect_episodes(parts, gap_threshold_s=2.0)
        assert len(boundaries) == 4

    def test_gap_at_threshold(self):
        # Gap exactly at threshold should NOT split (> not >=)
        part1 = _make_joint_samples(1, 500.0, start_ns=0)
        part2 = _make_joint_samples(1, 500.0, start_ns=int(2e9))  # exactly 2s
        joints = part1 + part2
        boundaries = detect_episodes(joints, gap_threshold_s=2.0)
        assert len(boundaries) == 1


class TestSplitByEpisodes:
    def test_splits_images_by_time_range(self):
        joints = _make_joint_samples(500, 500.0, start_ns=0)
        images = _make_image_samples(30, 30.0, start_ns=0)
        boundaries = [(0, 249), (250, 499)]  # Split in half
        episodes = split_by_episodes(joints, images, boundaries)
        assert len(episodes) == 2
        # All images should be in first episode (0 to ~0.5s)
        assert len(episodes[0][1]) > 0
