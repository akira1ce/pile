export const STAGE = { width: 1200, height: 720 };

/** Windows in front-to-back order, matching the switcher strip. */
export const WINDOW_ORDER = ["browse", "notes", "files"];

export const WINDOW_TITLES = {
  browse: "浏览",
  notes: "笔记",
  files: "文件",
};

export const INITIAL = {
  files: { x: 118, y: 150, w: 420, h: 282, z: 10 },
  notes: { x: 508, y: 256, w: 356, h: 248, z: 20 },
  browse: { x: 712, y: 108, w: 404, h: 272, z: 30 },
};

const PRESET = { w: 720, h: 518 };
const BASE = {
  x: (STAGE.width - PRESET.w) / 2,
  y: (STAGE.height - PRESET.h) / 2,
  w: PRESET.w,
  h: PRESET.h,
};

export const CENTERED = { ...BASE, z: INITIAL.browse.z };

export const STACK_GAP = 46;

/** Collapsed: every window sits exactly on the base frame. */
export function pileFrames() {
  return Object.fromEntries(
    WINDOW_ORDER.map((id) => [id, { ...BASE, z: INITIAL[id].z }])
  );
}

/** Expanded: the same frames cascaded by the configured spacing. */
export function expandedFrames() {
  return Object.fromEntries(
    WINDOW_ORDER.map((id, index) => [id, {
      ...BASE,
      x: BASE.x + index * STACK_GAP,
      y: BASE.y + index * STACK_GAP,
      z: INITIAL[id].z,
    }])
  );
}

export const SWITCHER_START = 1;
/** Tab steps through the remaining windows, ending on the committed one. */
export const SWITCHER_CYCLE = [2, 0, 1];
export const SWITCHER_COMMIT = SWITCHER_CYCLE[SWITCHER_CYCLE.length - 1];
