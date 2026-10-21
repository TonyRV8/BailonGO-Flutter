"""Symmetric floor guide: a five-cell cross, grown only where a step needs it."""

from dataclasses import dataclass

import numpy as np

CELL = 0.30
GAP = 0.02
FEET = (("L", 29, 31), ("R", 30, 32))
# Cell order: center, +x, -x, +y, -y (in units of CELL + GAP).
CROSS = np.array([(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)], dtype=float)
# The cross plus its four corners, in the order grow_layout would add them.
SQUARE = np.concatenate([CROSS, [(-1, -1), (1, -1), (-1, 1), (1, 1)]])
CENTER = 0
# A support is "on" a cell when its center lies within COVER cell pitches of
# it (Chebyshev), i.e. the foot overlaps the cell by at least about half.
COVER = 0.75
# The grid center is searched within this many pitches around the
# feet-together point and around the average support, keeping the one where
# the feet spend most of their support time inside a cell.
SEARCH = 0.5
SEARCH_STEPS = 11
# Score penalties: each extra cell beyond the cross, and each pitch the center
# moves away from the feet-together point (keeps the cross under the body).
CELL_COST = 0.03
SHIFT_COST = 0.05
# A foot halfway between two cells lights the inner one: the boundary is
# pushed this many pitches outward, so tiny numeric noise never flips it.
INNER_BIAS = 0.1
# Hand corrections where the recorded supports do not match the taught step:
# (foot, first frame, last frame, cell) with the cell in grid units from the
# center (+y is back) or None to keep the foot dark. Frames are inclusive.
STEP_OVERRIDES = {
    # After the turn the left foot's back step is not part of the guide.
    "vuelta_3d": (("L", 120, 134, None),),
    # The right foot only grazes the model's right cell on its way front.
    "toeheel_3d": (("R", 81, 84, None),),
}
# Per-step grid shape, passed to plan_guide: cell_scale enlarges cells and
# gaps, square starts from the 3x3 grid instead of the cross.
STEP_GRIDS = {
    # Bigger cells so the right foot's back reach ends inside the back
    # corner, which the cross alone would drop.
    "cumbia_3d": {"cell_scale": 1.3, "square": True},
    # Bigger cells so the left foot's long back steps land on the back cell
    # and the right foot stays inside the center before the turn.
    "vuelta_3d": {"cell_scale": 1.4},
    # Same cross and lights, just easier to see.
    "cuban_3d": {"cell_scale": 1.3},
    "toeheel_3d": {"cell_scale": 1.3},
}
# Extra supports where the recording keeps a foot in the air but the step
# plants it: (foot, first frame, last frame), inclusive. The rig lowers the
# foot to the floor there and the grid lights it like any other support.
STEP_CONTACTS = {
    # The left foot's back steps hover ~10 cm above the floor in the video.
    "vuelta_3d": (("L", 42, 54), ("L", 120, 129)),
}
# Steps where a cell both feet use lights in full with the foot's color
# instead of split in halves (the feet never share it at the same time).
STEP_SOLID_CELLS = {"cumbia_3d"}
# Steps whose second half must light exactly like the first one, mirrored:
# (first, last, shift) copies frames first..last onto first+shift..last+shift
# with feet swapped and x negated. Applied after STEP_OVERRIDES.
STEP_MIRRORS = {
    # The model's right half is the reference; its left half starts 80
    # frames later (the right foot's back taps land at 95 and 133).
    "cumbia_3d": (0, 76, 80),
}


def circular_runs(mask):
    """Keep a contact crossing the loop seam in one continuous run."""
    if not len(mask):
        return []
    if all(mask):
        return [list(range(len(mask)))]
    start = next(i for i, value in enumerate(mask) if not value)
    runs, current = [], []
    for offset in range(1, len(mask) + 1):
        frame = (start + offset) % len(mask)
        if mask[frame]:
            current.append(frame)
        elif current:
            runs.append(current)
            current = []
    return runs


@dataclass(frozen=True)
class FloorGuide:
    cell_size: float
    centers: np.ndarray
    assignments: dict

    def events(self):
        """One colored light for every recorded support, including returns."""
        return [(foot, cell, frames[0], frames)
                for foot, assigned in self.assignments.items()
                for cell in range(len(self.centers))
                for frames in circular_runs(assigned == cell)]


def base_position(positions, masks, scale):
    """Feet-together point, with the same criterion as process.py: both feet
    planted, level front/back and at a normal width. Falls back to the
    origin, which process.py already places at that point."""
    gap = positions["L"] - positions["R"]
    together = (masks["L"] & masks["R"] & (np.abs(gap[:, 1]) < 0.08 * scale)
                & (np.linalg.norm(gap, axis=1) < 0.3 * scale))
    if together.sum() >= 5:
        return np.median((positions["L"][together] +
                          positions["R"][together]) / 2, axis=0)
    return np.zeros(2)


def support_runs(positions, masks):
    """(foot, frames, median position) for every continuous support."""
    return [(foot, frames, np.median(positions[foot][frames], axis=0))
            for foot in masks for frames in circular_runs(masks[foot])]


def mean_support(runs):
    """Average support position, weighted by how long each support lasts."""
    weights = np.array([len(frames) for _, frames, _ in runs], dtype=float)
    return np.average([where for _, _, where in runs], axis=0, weights=weights)


def mirrored(x, y):
    """A cell, the cells joining it to the cross, and their mirror images."""
    path = ({(i, 0) for i in range(0, abs(x) + 1)} |
            {(abs(x), j) for j in range(0, abs(y) + 1)})
    return {(sx * i, sy * j) for i, j in path for sx in (1, -1) for sy in (1, -1)}


def grow_layout(points, start=CROSS):
    """Start from the cross and add (mirrored) cells for uncovered supports."""
    cells = [tuple(map(int, c)) for c in start]
    for q in sorted(points, key=lambda q: float(np.abs(q).max())):
        if np.abs(np.asarray(cells) - q).max(axis=1).min() <= COVER:
            continue
        x, y = np.rint(q).astype(int)
        extra = mirrored(x, y) - set(cells)
        cells += sorted(extra, key=lambda c: (abs(c[0]) + abs(c[1]), c[1], c[0]))
    return np.asarray(cells, dtype=float)


def fit_grid(center, runs, positions, pitch, cell_size, start):
    """(fraction of support frames inside their cell, centers, cell per run)."""
    layout = grow_layout([(where - center) / pitch for _, _, where in runs], start)
    centers = center + layout * pitch
    ring = np.abs(layout).max(axis=1)
    choice, inside, total = [], 0, 0
    for foot, frames, where in runs:
        score = np.linalg.norm(centers - where, axis=1) / pitch + INNER_BIAS * ring
        cell = int(np.argmin(score))
        error = np.abs(positions[foot][frames] - centers[cell]).max(axis=1)
        inside += int(np.sum(error <= cell_size / 2))
        total += len(frames)
        choice.append(cell)
    return inside / total, centers, choice


def step_contacts(name, contacts):
    """Contact masks with the step's extra supports added (copies only)."""
    extra = STEP_CONTACTS.get(name, ())
    if not extra:
        return contacts
    result = {foot: list(mask) for foot, mask in contacts.items()}
    for foot, first, last in extra:
        for t in range(first, last + 1):
            result[foot][t % len(result[foot])] = True
    return result


def apply_overrides(assigned, centers, pitch, overrides):
    """Relight frames by hand without changing the grid layout."""
    if not len(centers):
        return
    layout = {tuple(np.rint((c - centers[0]) / pitch).astype(int)): i
              for i, c in enumerate(centers)}
    for foot, first, last, cell in overrides:
        if cell is not None and tuple(cell) not in layout:
            raise ValueError(f"No grid cell at {cell}")
        frames = np.arange(first, last + 1) % len(assigned[foot])
        assigned[foot][frames] = -1 if cell is None else layout[tuple(cell)]


def apply_mirror(assigned, centers, pitch, mirror):
    """Light one span like an earlier one, with feet and sides swapped."""
    if mirror is None or not len(centers):
        return
    first, last, shift = mirror
    cells = [tuple(np.rint((c - centers[0]) / pitch).astype(int)) for c in centers]
    opposite = [cells.index((-x, y)) for x, y in cells]
    source = {foot: assigned[foot].copy() for foot in assigned}
    for foot, other in (("L", "R"), ("R", "L")):
        for t in range(first, last + 1):
            cell = source[foot][t % len(source[foot])]
            assigned[other][(t + shift) % len(assigned[other])] = \
                -1 if cell < 0 else opposite[cell]


def plan_guide(joints, frame_count, contacts, scale=1.0, overrides=(),
               mirror=None, cell_scale=1.0, square=False):
    """Lay a symmetric grid around the step and light the cell each support hits.

    Contact masks are the same ones that lock the rig's feet to the floor.
    The grid is a cross that grows (always mirrored left/right and front/back)
    only where a support would otherwise miss every cell. Every support run is
    assigned as a whole (by its median position) to the nearest cell, so a
    planted foot never flickers between two cells.
    """
    if scale <= 0:
        raise ValueError("Guide scale must be positive")
    joints = np.asarray(joints)
    masks = {foot: np.asarray(contacts[foot][:frame_count], dtype=bool)
             for foot, _, _ in FEET}
    positions = {foot: (joints[:frame_count, heel, :2] +
                        joints[:frame_count, toe, :2]) / 2
                 for foot, heel, toe in FEET}
    assigned = {foot: np.full(frame_count, -1, dtype=int) for foot, _, _ in FEET}
    runs = support_runs(positions, masks)
    cell_size = CELL * scale * cell_scale
    if not runs:
        return FloorGuide(cell_size, np.empty((0, 2)), assigned)

    pitch = (CELL + GAP) * scale * cell_scale
    start = SQUARE if square else CROSS
    base = base_position(positions, masks, scale)
    offsets = np.linspace(-SEARCH, SEARCH, SEARCH_STEPS) * pitch
    best = None
    for anchor in (base, mean_support(runs)):
        for dx in offsets:
            for dy in offsets:
                fit = fit_grid(anchor + (dx, dy), runs, positions, pitch,
                               cell_size, start)
                score = (fit[0] - CELL_COST * (len(fit[1]) - len(start))
                         - SHIFT_COST * np.linalg.norm(anchor + (dx, dy) - base) / pitch)
                if best is None or score > best[0] + 1e-12:
                    best = (score, fit)
    _, (_, centers, choice) = best
    for (foot, frames, _), cell in zip(runs, choice):
        assigned[foot][frames] = cell
    apply_overrides(assigned, centers, pitch, overrides)
    apply_mirror(assigned, centers, pitch, mirror)
    return FloorGuide(cell_size, centers, assigned)
