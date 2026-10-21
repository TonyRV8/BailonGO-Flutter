"""Run with: python tool/anim3d/test_dance_grid.py."""
import json
from pathlib import Path
import struct
import unittest

import numpy as np

from dance_grid import (CELL, CENTER, COVER, GAP, FEET, STEP_CONTACTS, STEP_GRIDS,
                        STEP_MIRRORS, STEP_OVERRIDES, STEP_SOLID_CELLS,
                        circular_runs,
                        plan_guide, step_contacts)

from foot_pitch import FOOT_LENGTH, STEP_HEIGHT_PITCH, TAP_LIMIT, height_pitch, tap_pitch

ROOT = Path(__file__).resolve().parents[2]


def foot_positions(joints, foot):
    _, heel, toe = next(item for item in FEET if item[0] == foot)
    return (joints[:, heel, :2] + joints[:, toe, :2]) / 2


class GuideTests(unittest.TestCase):
    def fixture(self, count=24):
        joints = np.zeros((count, 33, 3))
        return joints, {"L": np.ones(count, bool), "R": np.ones(count, bool)}

    def assert_lit(self, guide, contacts):
        for foot, assigned in guide.assignments.items():
            np.testing.assert_array_equal(assigned >= 0, np.asarray(contacts[foot], bool))

    def test_cells_are_a_bit_bigger_than_the_first_cross(self):
        self.assertGreater(CELL, 0.26)
        self.assertLess(CELL, 0.40)
        self.assertLess(GAP, 0.04)

    def test_layout_is_a_five_cell_cross_around_the_base(self):
        joints, contacts = self.fixture()
        joints[:, (29, 31), :2] = (0.07, 0.1)
        joints[:, (30, 32), :2] = (-0.09, 0.1)
        guide = plan_guide(joints, 24, contacts)
        pitch = CELL + GAP
        base = np.array([-0.01, 0.1])
        expected = base + np.array([(0, 0), (pitch, 0), (-pitch, 0), (0, pitch), (0, -pitch)])
        np.testing.assert_allclose(guide.centers, expected, atol=1e-9)
        self.assertEqual(guide.assignments["L"][0], CENTER)
        self.assertEqual(guide.assignments["R"][0], CENTER)

    def test_steps_light_the_arm_they_land_on(self):
        pitch = CELL + GAP
        for offset, cell in (((pitch, 0), 1), ((-pitch, 0), 2),
                             ((0, pitch), 3), ((0, -pitch), 4)):
            with self.subTest(offset=offset):
                joints, contacts = self.fixture()
                contacts["L"][8:16] = False
                contacts["R"][:8] = False
                contacts["R"][16:] = False
                joints[8:16, (30, 32), :2] = np.array(offset) * 0.9
                guide = plan_guide(joints, 24, contacts)
                np.testing.assert_array_equal(guide.assignments["R"][8:16], cell)
                self.assert_lit(guide, contacts)

    def test_one_support_never_chatters_between_cells(self):
        joints, contacts = self.fixture()
        contacts["R"][:] = False
        boundary = (CELL + GAP) / 2
        joints[:, (29, 31), 0] = (boundary + np.linspace(-0.02, 0.02, 24))[:, None]
        guide = plan_guide(joints, 24, contacts)
        self.assertEqual(len(set(guide.assignments["L"])), 1)

    def test_swing_frames_stay_dark(self):
        joints, contacts = self.fixture()
        contacts["L"][8:16] = False
        joints[8:16, (29, 31), :2] = (3, 3)
        guide = plan_guide(joints, 24, contacts)
        np.testing.assert_array_equal(guide.assignments["L"][8:16], -1)
        self.assert_lit(guide, contacts)

    def test_overrides_light_darken_or_move_a_support(self):
        joints, contacts = self.fixture()
        contacts["R"][8:12] = False
        plain = plan_guide(joints, 24, contacts)
        overrides = (("R", 8, 11, (0, 1)), ("L", 0, 3, None), ("L", 4, 5, (1, 0)))
        guide = plan_guide(joints, 24, contacts, overrides=overrides)
        np.testing.assert_allclose(guide.centers, plain.centers)
        np.testing.assert_array_equal(guide.assignments["R"][8:12], 3)
        np.testing.assert_array_equal(guide.assignments["L"][0:4], -1)
        np.testing.assert_array_equal(guide.assignments["L"][4:6], 1)
        np.testing.assert_array_equal(guide.assignments["L"][6:], plain.assignments["L"][6:])

    def test_mirror_copies_one_half_onto_the_other_foot_and_side(self):
        joints, contacts = self.fixture()
        contacts["R"][:] = False
        joints[:, (29, 31), 0] = -(CELL + GAP)
        guide = plan_guide(joints, 24, contacts, mirror=(0, 5, 12))
        np.testing.assert_array_equal(guide.assignments["L"][0:6], 2)
        np.testing.assert_array_equal(guide.assignments["R"][12:18], 1)
        np.testing.assert_array_equal(guide.assignments["L"][12:18], -1)
        np.testing.assert_array_equal(guide.assignments["R"][0:12], -1)

    def test_bigger_cells_scale_the_whole_grid(self):
        joints, contacts = self.fixture()
        plain = plan_guide(joints, 24, contacts)
        big = plan_guide(joints, 24, contacts, cell_scale=1.3)
        self.assertAlmostEqual(big.cell_size, CELL * 1.3)
        np.testing.assert_allclose(big.centers - big.centers[0],
                                   (plain.centers - plain.centers[0]) * 1.3)

    def test_square_layout_keeps_the_four_corners(self):
        joints, contacts = self.fixture()
        guide = plan_guide(joints, 24, contacts, square=True)
        pitch = CELL + GAP
        cells = {tuple(np.rint((c - guide.centers[0]) / pitch).astype(int))
                 for c in guide.centers}
        self.assertEqual(cells, {(x, y) for x in (-1, 0, 1) for y in (-1, 0, 1)})

    def test_override_to_a_missing_cell_fails_loudly(self):
        joints, contacts = self.fixture()
        with self.assertRaises(ValueError):
            plan_guide(joints, 24, contacts, overrides=(("L", 0, 3, (2, 2)),))

    def test_no_contacts_means_no_distracting_grid(self):
        joints, contacts = self.fixture()
        contacts["L"][:] = False
        contacts["R"][:] = False
        guide = plan_guide(joints, 24, contacts)
        self.assertEqual(len(guide.centers), 0)
        self.assertEqual(guide.events(), [])

    def test_layout_scales_with_the_character(self):
        joints, contacts = self.fixture()
        joints[8:16, (29, 31), :2] = (0.3, -0.3)
        original = plan_guide(joints, 24, contacts)
        small = plan_guide(joints * 0.803, 24, contacts, scale=0.803)
        np.testing.assert_allclose(small.centers, original.centers * 0.803)
        self.assertAlmostEqual(small.cell_size, CELL * 0.803)
        for foot in FEET:
            np.testing.assert_array_equal(small.assignments[foot[0]],
                                          original.assignments[foot[0]])

    def test_planning_does_not_modify_the_dance(self):
        joints, contacts = self.fixture()
        before = joints.copy()
        plan_guide(joints, 24, contacts)
        np.testing.assert_array_equal(joints, before)

    def test_contact_across_loop_seam_remains_one_event(self):
        self.assertEqual(circular_runs([True, True, False, True]), [[3, 0, 1]])
        self.assertEqual(circular_runs([True] * 4), [[0, 1, 2, 3]])
        self.assertEqual(circular_runs([False] * 4), [])

    def test_foot_halfway_to_an_arm_prefers_the_inner_cell(self):
        pitch = CELL + GAP
        for shift in (-0.02, 0.0, 0.02):
            with self.subTest(shift=shift):
                joints, contacts = self.fixture()
                contacts["L"][8:16] = False
                contacts["R"][:8] = False
                contacts["R"][16:] = False
                joints[8:16, (30, 32), 0] = (0.5 + shift) * pitch
                guide = plan_guide(joints, 24, contacts)
                self.assertEqual(guide.assignments["R"][10], CENTER)

    def assert_inside_symmetric(self, guide, joints, contacts):
        pitch = CELL + GAP
        cells = {tuple(np.rint((c - guide.centers[0]) / pitch).astype(int))
                 for c in guide.centers}
        for x, y in cells:
            self.assertTrue({(-x, y), (x, -y), (-x, -y)} <= cells)
        for foot in contacts:
            for i in np.flatnonzero(contacts[foot]):
                cell = guide.centers[guide.assignments[foot][i]]
                self.assertLessEqual(np.max(np.abs(foot_positions(joints, foot)[i] - cell)),
                                     guide.cell_size / 2 + 1e-9)

    def test_far_side_and_diagonal_steps_land_inside_a_symmetric_grid(self):
        pitch = CELL + GAP
        for offset in ((1.8, 0), (0, -2.1), (1, 1), (-1.4, 0.9)):
            with self.subTest(offset=offset):
                joints, contacts = self.fixture()
                contacts["L"][8:16] = False
                contacts["R"][:8] = False
                contacts["R"][16:] = False
                joints[8:16, (30, 32), :2] = np.array(offset) * pitch
                guide = plan_guide(joints, 24, contacts)
                self.assert_inside_symmetric(guide, joints, contacts)

    def test_feet_already_inside_keep_the_cross_under_the_body(self):
        joints, contacts = self.fixture()
        joints[:, (29, 31), :2] = (0.07, 0.04)
        joints[:, (30, 32), :2] = (-0.07, 0.04)
        guide = plan_guide(joints, 24, contacts)
        np.testing.assert_allclose(guide.centers[0], (0, 0.04), atol=1e-9)
        self.assertEqual(len(guide.centers), 5)

    def test_lopsided_travel_recenters_on_the_motion(self):
        pitch = CELL + GAP
        joints, contacts = self.fixture()
        contacts["L"][:] = False
        contacts["L"][8:16] = True
        contacts["R"][8:16] = False
        joints[:, (29, 31), 0] = -3.5 * pitch
        joints[:, (30, 32), 0] = 0.5 * pitch
        guide = plan_guide(joints, 24, contacts)
        self.assertLess(guide.centers[0][0], -0.5 * pitch)

    def test_every_recorded_support_lands_on_a_symmetric_grid(self):
        pitch = CELL + GAP
        data = json.loads((ROOT / "tool/anim3d/clean.json").read_text())
        for name, step in data.items():
            for scale in (1.0, 0.803):
                with self.subTest(step=name, scale=scale):
                    joints = np.asarray(step["joints"]) * scale
                    contacts = {foot: step["contact_" + foot] for foot, _, _ in FEET}
                    guide = plan_guide(joints, len(joints), contacts, scale)
                    self.assert_lit(guide, contacts)
                    cells = {tuple(np.rint((c - guide.centers[0]) / (pitch * scale)).astype(int))
                             for c in guide.centers}
                    self.assertEqual(len(cells), len(guide.centers))
                    for x, y in cells:
                        self.assertTrue({(-x, y), (x, -y), (-x, -y)} <= cells)
                    if name in ("basico_3d", "guapeo_3d"):
                        self.assertEqual(len(cells), 5)
                    inside = [np.max(np.abs(foot_positions(joints, f)[i] -
                                            guide.centers[guide.assignments[f][i]]))
                              <= guide.cell_size / 2 + 1e-9
                              for f in contacts for i in np.flatnonzero(contacts[f])]
                    self.assertGreaterEqual(np.mean(inside), 0.95)
                    used = {int(c) for a in guide.assignments.values() for c in a if c >= 0}
                    extra = set(range(5, len(guide.centers)))
                    # Cells added beyond the cross must mostly earn their place;
                    # only mirror images of real supports may stay empty.
                    self.assertLessEqual(len(extra - used), len(extra) // 2)
                    for foot, _, heel_toe in FEET:
                        position = foot_positions(joints, foot)
                        for frames in circular_runs(contacts[foot]):
                            self.assertEqual(len(set(guide.assignments[foot][frames])), 1)
                            where = np.median(position[frames], axis=0)
                            cell = guide.centers[guide.assignments[foot][frames[0]]]
                            self.assertLessEqual(np.max(np.abs(where - cell)) / (pitch * scale),
                                                 COVER + 1e-9)


class FootPitchTests(unittest.TestCase):
    def test_pitch_follows_heel_and_toe_heights(self):
        heel = np.array([0.0, 0.05, 0.0, 0.0])
        toe = np.array([0.0, 0.0, 0.05, 0.4])
        np.testing.assert_allclose(height_pitch(heel, toe, 0.2),
                                   [0.0, -14.4775, 14.4775, 90.0], atol=1e-3)

    def test_tap_pitch_makes_taps_visible_and_keeps_flat_feet_flat(self):
        heel = np.array([0.0, 0.003, 0.07, 0.0, 0.0])
        toe = np.array([0.0, 0.0, 0.0, 0.07, 0.2])
        pitch = tap_pitch(heel, toe, 0.2)
        self.assertEqual(pitch[0], 0.0)
        self.assertEqual(pitch[1], 0.0)
        self.assertLess(pitch[2], -40)
        self.assertGreater(pitch[3], 40)
        self.assertEqual(pitch[4], TAP_LIMIT)

    def test_toeheel_follows_the_landmark_heights(self):
        step = json.loads((ROOT / "tool/anim3d/clean.json").read_text())["toeheel_3d"]
        joints = np.asarray(step["joints"])
        self.assertEqual(STEP_HEIGHT_PITCH, {"toeheel_3d"})
        for foot, heel, toe in FEET:
            dz = joints[:, toe, 2] - joints[:, heel, 2]
            pitch = tap_pitch(joints[:, heel, 2], joints[:, toe, 2], FOOT_LENGTH)
            clear = np.abs(dz) > 0.015
            self.assertGreaterEqual(np.mean(np.sign(pitch[clear]) == np.sign(dz[clear])), 0.99)


class StepOverrideTests(unittest.TestCase):
    def test_cumbia_lights_match_the_taught_step(self):
        step = json.loads((ROOT / "tool/anim3d/clean.json").read_text())["cumbia_3d"]
        joints = np.asarray(step["joints"])
        contacts = {foot: step["contact_" + foot] for foot, _, _ in FEET}
        grid = STEP_GRIDS["cumbia_3d"]
        guide = plan_guide(joints, len(joints), contacts,
                           mirror=STEP_MIRRORS["cumbia_3d"], **grid)
        pitch = (CELL + GAP) * grid["cell_scale"]
        cells = [tuple(np.rint((c - guide.centers[0]) / pitch).astype(int))
                 for c in guide.centers]
        index = {cell: i for i, cell in enumerate(cells)}
        # Left foot between its back taps belongs to the center cell.
        np.testing.assert_array_equal(guide.assignments["L"][33:44], CENTER)
        # The right foot's back reach ends inside the back corner it lights.
        right = foot_positions(joints, "R")
        for t in list(range(95, 102)) + list(range(133, 140)):
            self.assertEqual(guide.assignments["R"][t], index[(1, 1)])
            self.assertLessEqual(np.abs(right[t] - guide.centers[index[(1, 1)]]).max(),
                                 guide.cell_size / 2)
        # The model's left half repeats its right half, 80 frames later.
        first, last, shift = STEP_MIRRORS["cumbia_3d"]
        for t in range(first, last + 1):
            for foot, other in (("L", "R"), ("R", "L")):
                source = guide.assignments[foot][t]
                expected = -1 if source < 0 else index[(-cells[source][0], cells[source][1])]
                self.assertEqual(guide.assignments[other][t + shift], expected, (foot, t))

    def test_vuelta_left_foot_plants_its_back_steps(self):
        step = json.loads((ROOT / "tool/anim3d/clean.json").read_text())["vuelta_3d"]
        joints = np.asarray(step["joints"])
        contacts = step_contacts("vuelta_3d",
                                 {foot: step["contact_" + foot] for foot, _, _ in FEET})
        guide = plan_guide(joints, len(joints), contacts,
                           overrides=STEP_OVERRIDES["vuelta_3d"], **STEP_GRIDS["vuelta_3d"])
        pitch = (CELL + GAP) * STEP_GRIDS["vuelta_3d"]["cell_scale"]
        cells = [tuple(np.rint((c - guide.centers[0]) / pitch).astype(int))
                 for c in guide.centers]
        # Before the turn the right foot stays inside the center, never
        # grazing the model's right cell.
        side = cells.index((-1, 0))
        self.assertFalse(np.any(guide.assignments["R"] == side))
        self.assertFalse(np.any(guide.assignments["L"] == side))
        left = foot_positions(joints, "L")
        for t in range(42, 55):
            cell = guide.assignments["L"][t]
            self.assertEqual(cells[cell], (0, 1), t)
            self.assertLessEqual(np.abs(left[t] - guide.centers[cell]).max(),
                                 guide.cell_size / 2, t)
        # After the turn the left foot still plants back, but stays dark.
        self.assertTrue(all(contacts["L"][120:135]))
        np.testing.assert_array_equal(guide.assignments["L"][120:135], -1)

    def test_cuban_uses_a_bigger_cross_with_every_support_inside(self):
        step = json.loads((ROOT / "tool/anim3d/clean.json").read_text())["cuban_3d"]
        joints = np.asarray(step["joints"])
        contacts = {foot: step["contact_" + foot] for foot, _, _ in FEET}
        plain = plan_guide(joints, len(joints), contacts)
        guide = plan_guide(joints, len(joints), contacts, **STEP_GRIDS["cuban_3d"])
        self.assertAlmostEqual(guide.cell_size, CELL * 1.3)
        self.assertEqual(len(guide.centers), 5)
        for foot in contacts:
            np.testing.assert_array_equal(guide.assignments[foot], plain.assignments[foot])
            for t in np.flatnonzero(contacts[foot]):
                where = foot_positions(joints, foot)[t]
                cell = guide.centers[guide.assignments[foot][t]]
                self.assertLessEqual(np.abs(where - cell).max(), guide.cell_size / 2)

    def test_toeheel_bigger_cross_without_the_side_graze(self):
        step = json.loads((ROOT / "tool/anim3d/clean.json").read_text())["toeheel_3d"]
        joints = np.asarray(step["joints"])
        contacts = {foot: step["contact_" + foot] for foot, _, _ in FEET}
        guide = plan_guide(joints, len(joints), contacts,
                           overrides=STEP_OVERRIDES["toeheel_3d"], **STEP_GRIDS["toeheel_3d"])
        self.assertAlmostEqual(guide.cell_size, CELL * 1.3)
        pitch = (CELL + GAP) * 1.3
        cells = [tuple(np.rint((c - guide.centers[0]) / pitch).astype(int))
                 for c in guide.centers]
        self.assertEqual(len(cells), 5)
        side = cells.index((-1, 0))
        self.assertFalse(np.any(guide.assignments["R"] == side))
        # Toe taps back with the left foot, heel taps front with the right.
        np.testing.assert_array_equal(guide.assignments["L"][41:47], cells.index((0, 1)))
        np.testing.assert_array_equal(guide.assignments["L"][151:159], cells.index((0, 1)))
        np.testing.assert_array_equal(guide.assignments["R"][94:102], cells.index((0, -1)))
        # Both feet share the center at once, so its halves keep both colors.
        self.assertNotIn("toeheel_3d", STEP_SOLID_CELLS)

    def test_step_contacts_add_supports_without_touching_the_data(self):
        original = {"L": [False] * 140, "R": [True] * 140}
        contacts = step_contacts("vuelta_3d", original)
        self.assertTrue(all(contacts["L"][42:55]))
        self.assertFalse(any(contacts["L"][:42]))
        self.assertEqual(original["L"], [False] * 140)
        self.assertIs(step_contacts("basico_3d", original)["L"], original["L"])

    def test_only_cumbia_and_vuelta_are_hand_tuned_for_now(self):
        self.assertEqual(set(STEP_OVERRIDES), {"vuelta_3d", "toeheel_3d"})
        self.assertEqual(set(STEP_MIRRORS), {"cumbia_3d"})
        self.assertEqual(set(STEP_GRIDS), {"cumbia_3d", "vuelta_3d", "cuban_3d", "toeheel_3d"})
        self.assertEqual(set(STEP_CONTACTS), {"vuelta_3d"})


def glb_document(path):
    with path.open("rb") as stream:
        magic, version, _ = struct.unpack("<III", stream.read(12))
        assert magic == 0x46546C67 and version == 2
        size, _ = struct.unpack("<II", stream.read(8))
        document = json.loads(stream.read(size))
        size, _ = struct.unpack("<II", stream.read(8))
        binary = stream.read(size)
    return document, binary


def accessor_values(doc, binary, index):
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    width = {"SCALAR": 1, "VEC3": 3}[accessor["type"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", width * 4)
    return np.asarray([struct.unpack_from("<" + "f" * width, binary, offset + i * stride)
                       for i in range(accessor["count"])])


def sampled_channels(doc, binary, animation, frame_count):
    result = {}
    times = np.arange(frame_count) / 30
    for channel in animation["channels"]:
        if channel["target"]["path"] not in ("scale", "translation"):
            continue
        sampler = animation["samplers"][channel["sampler"]]
        t = accessor_values(doc, binary, sampler["input"])[:, 0]
        values = accessor_values(doc, binary, sampler["output"])
        result[(channel["target"]["node"], channel["target"]["path"])] = np.column_stack([
            np.interp(times, t, values[:, axis]) for axis in range(3)])
    return result


class ExportedGridTests(unittest.TestCase):
    def test_exported_clips_reset_layout_and_light_every_support(self):
        data = json.loads((ROOT / "tool/anim3d/clean.json").read_text())
        for filename in ("Claire.glb", "DanceGrid1.glb"):
            doc, binary = glb_document(ROOT / "assets/models" / filename)
            nodes = doc["nodes"]
            cells = {int(node["name"].split("_")[1]): i for i, node in enumerate(nodes)
                     if node.get("name", "").startswith("casilla_")}
            self.assertTrue(cells, filename)
            first = nodes[cells[0]]
            primitive = doc["meshes"][first["mesh"]]["primitives"][0]
            vertices = accessor_values(doc, binary, primitive["attributes"]["POSITION"])
            cell_size = float(np.ptp(vertices[:, 0]))
            scale = cell_size / CELL
            self.assertEqual({a["name"] for a in doc["animations"]}, set(data))
            for animation in doc["animations"]:
                with self.subTest(model=filename, step=animation["name"]):
                    step = data[animation["name"]]
                    count = step["frames"]
                    joints = np.asarray(step["joints"]) * scale
                    contacts = step_contacts(animation["name"],
                                             {foot: step["contact_" + foot] for foot, _, _ in FEET})
                    guide = plan_guide(joints, count, contacts, scale,
                                       overrides=STEP_OVERRIDES.get(animation["name"], ()),
                                       mirror=STEP_MIRRORS.get(animation["name"]),
                                       **STEP_GRIDS.get(animation["name"], {}))
                    size = guide.cell_size / (CELL * scale)
                    channels = sampled_channels(doc, binary, animation, count)
                    for cell, node in cells.items():
                        active = cell < len(guide.centers)
                        np.testing.assert_allclose(channels[(node, "scale")],
                                                   size if active else 0.001, atol=1e-6)
                        if active:
                            xy = guide.centers[cell]
                            expected = np.tile((xy[0], 0, -xy[1]), (count, 1))
                            np.testing.assert_allclose(channels[(node, "translation")], expected, atol=1e-6)
                        for foot, tag in (("L", "izq"), ("R", "der")):
                            pad = next(i for i, item in enumerate(nodes)
                                       if item.get("name") == f"pisada_{cell}_pie_{tag}")
                            self.assertIn((pad, "translation"), channels)
                            lit = channels[(pad, "scale")][:, 1] > 0.99
                            np.testing.assert_array_equal(lit, guide.assignments[foot] == cell)


class ExportedSolidCellTests(unittest.TestCase):
    def test_solid_steps_light_shared_cells_in_full(self):
        for filename in ("Claire.glb", "DanceGrid1.glb"):
            doc, binary = glb_document(ROOT / "assets/models" / filename)
            names = {node.get("name"): i for i, node in enumerate(doc["nodes"])}
            for animation in doc["animations"]:
                channels = sampled_channels(doc, binary, animation, 60)
                pad = channels[(names["pisada_0_pie_izq"], "scale")]
                shift = channels[(names["pisada_0_pie_izq"], "translation")]
                solid = animation["name"] in STEP_SOLID_CELLS
                with self.subTest(model=filename, step=animation["name"]):
                    if solid:
                        np.testing.assert_allclose(pad[:, 0], pad[:, 1], atol=1e-6)
                        np.testing.assert_allclose(shift[:, 0], 0, atol=1e-6)

    def test_only_cumbia_lights_shared_cells_in_full(self):
        self.assertEqual(set(STEP_SOLID_CELLS), {"cumbia_3d"})


if __name__ == "__main__":
    unittest.main()
