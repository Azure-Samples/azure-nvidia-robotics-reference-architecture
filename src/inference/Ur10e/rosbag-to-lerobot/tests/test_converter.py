"""Tests for the conversion pipeline."""

from __future__ import annotations

import numpy as np

from rosbag_to_lerobot.converter import compute_action_deltas


class TestComputeActionDeltas:
    def test_basic_deltas(self):
        s0 = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
        s1 = np.array([1.5, 2.5, 3.5, 4.5, 5.5, 6.5])
        s2 = np.array([2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
        deltas = compute_action_deltas([s0, s1, s2])
        np.testing.assert_allclose(deltas[0], s1 - s0)
        np.testing.assert_allclose(deltas[1], s2 - s1)

    def test_last_frame_zero(self):
        states = [np.ones(6), np.ones(6) * 2]
        deltas = compute_action_deltas(states)
        np.testing.assert_allclose(deltas[-1], np.zeros(6))

    def test_single_frame(self):
        states = [np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])]
        deltas = compute_action_deltas(states)
        assert len(deltas) == 1
        np.testing.assert_allclose(deltas[0], np.zeros(6))

    def test_output_length(self):
        states = [np.ones(6) * i for i in range(10)]
        deltas = compute_action_deltas(states)
        assert len(deltas) == len(states)
