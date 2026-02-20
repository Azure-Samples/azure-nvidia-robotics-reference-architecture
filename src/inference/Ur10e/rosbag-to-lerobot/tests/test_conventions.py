"""Tests for joint coordinate conventions and image preprocessing."""

from __future__ import annotations

import numpy as np

from rosbag_to_lerobot.conventions import (
    apply_joint_sign,
    convert_joint_positions,
    resize_image,
    wrap_to_pi,
)


class TestApplyJointSign:
    def test_negate_shoulder_elbow(self):
        positions = np.array([1.0, 2.0, -3.0, 4.0, 5.0, 6.0])
        mask = [1.0, -1.0, -1.0, 1.0, 1.0, 1.0]
        result = apply_joint_sign(positions, mask)
        expected = np.array([1.0, -2.0, 3.0, 4.0, 5.0, 6.0])
        np.testing.assert_allclose(result, expected)

    def test_identity_mask(self):
        positions = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
        mask = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        result = apply_joint_sign(positions, mask)
        np.testing.assert_allclose(result, positions)

    def test_batch_input(self):
        positions = np.array([[1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [6.0, 5.0, 4.0, 3.0, 2.0, 1.0]])
        mask = [1.0, -1.0, -1.0, 1.0, 1.0, 1.0]
        result = apply_joint_sign(positions, mask)
        expected = np.array([[1.0, -2.0, -3.0, 4.0, 5.0, 6.0], [6.0, -5.0, -4.0, 3.0, 2.0, 1.0]])
        np.testing.assert_allclose(result, expected)


class TestWrapToPi:
    def test_within_range_unchanged(self):
        angles = np.array([0.0, 1.0, -1.0, 3.0, -3.0])
        result = wrap_to_pi(angles)
        np.testing.assert_allclose(result, angles, atol=1e-7)

    def test_positive_overflow(self):
        result = wrap_to_pi(np.array([4.0]))
        assert -np.pi < float(result[0]) <= np.pi

    def test_negative_overflow(self):
        result = wrap_to_pi(np.array([-4.0]))
        assert -np.pi < float(result[0]) <= np.pi

    def test_multiples_of_2pi(self):
        result = wrap_to_pi(np.array([6 * np.pi]))
        np.testing.assert_allclose(result, [0.0], atol=1e-7)

    def test_zero_unchanged(self):
        result = wrap_to_pi(np.array([0.0]))
        np.testing.assert_allclose(result, [0.0], atol=1e-7)


class TestConvertJointPositions:
    def test_full_pipeline(self):
        positions = np.array([1.0, 2.0, -3.0, 4.0, 5.0, 6.0])
        result = convert_joint_positions(positions, sign_mask=[1, -1, -1, 1, 1, 1], wrap=True)
        # After sign flip: [1, -2, 3, 4, 5, 6], then wrap to (-pi, pi]
        assert result.dtype == np.float32
        assert result.shape == (6,)
        for val in result:
            assert -np.pi <= float(val) <= np.pi + 1e-7

    def test_no_sign_mask(self):
        positions = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
        result = convert_joint_positions(positions, sign_mask=None, wrap=True)
        assert result.dtype == np.float32

    def test_no_wrap(self):
        positions = np.array([1.0, 2.0, 10.0, 4.0, 5.0, 6.0])
        result = convert_joint_positions(positions, sign_mask=None, wrap=False)
        np.testing.assert_allclose(result, positions, atol=1e-6)

    def test_output_dtype(self):
        positions = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], dtype=np.float64)
        result = convert_joint_positions(positions)
        assert result.dtype == np.float32


class TestResizeImage:
    def test_downscale(self):
        image = np.zeros((640, 480, 3), dtype=np.uint8)
        result = resize_image(image, (480, 848))
        assert result.shape == (480, 848, 3)

    def test_upscale(self):
        image = np.zeros((100, 100, 3), dtype=np.uint8)
        result = resize_image(image, (480, 848))
        assert result.shape == (480, 848, 3)

    def test_preserves_dtype(self):
        image = np.zeros((640, 480, 3), dtype=np.uint8)
        result = resize_image(image, (480, 848))
        assert result.dtype == np.uint8
