"""Foot pitch from heel and toe heights, for steps that live on toe and heel.

MediaPipe flattens depth, so the heel-to-toe horizontal length comes out a
few centimeters long and atan2(height, length) swings wildly. Heights are
reliable: the pitch is the angle whose sine is the height difference over
the real foot length.
"""

import numpy as np

# Heel to foot_index landmark distance of an adult foot, in data meters.
FOOT_LENGTH = 0.20
# Steps whose foot pitch is driven by heel/toe heights instead of the
# deviation from the median supported pitch.
STEP_HEIGHT_PITCH = {"toeheel_3d"}
# The video only lifts heel or toe 4-8 cm (about 20 degrees), too subtle to
# read as a tap: pitch beyond a small dead zone is amplified up to a limit.
TAP_DEAD = 3.0
TAP_GAIN = 2.6
TAP_LIMIT = 55.0


def height_pitch(heel_z, toe_z, foot_length):
    """Degrees per frame; positive lifts the toe, negative points it down."""
    dz = np.asarray(toe_z, float) - np.asarray(heel_z, float)
    return np.degrees(np.arcsin(np.clip(dz / foot_length, -1.0, 1.0)))


def tap_pitch(heel_z, toe_z, foot_length):
    """height_pitch with taps exaggerated so toe and heel touches show."""
    pitch = height_pitch(heel_z, toe_z, foot_length)
    lift = np.maximum(np.abs(pitch) - TAP_DEAD, 0.0) * TAP_GAIN
    return np.sign(pitch) * np.minimum(lift, TAP_LIMIT)
