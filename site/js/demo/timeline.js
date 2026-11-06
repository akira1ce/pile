import { animate } from "../motion.js";
import { applyFrame, setFocus } from "./stage.js";
import {
  CENTERED,
  INITIAL,
  SWITCHER_COMMIT,
  SWITCHER_CYCLE,
  SWITCHER_START,
  WINDOW_ORDER,
  expandedFrames,
  pileFrames,
} from "./layouts.js";

const SPRING = { type: "spring", stiffness: 150, damping: 26 };
const EASE_OUT = [0.22, 1, 0.36, 1];

let animations = [];

function play(...args) {
  const controls = animate(...args);
  animations.push(controls);
  return controls;
}

export function cancelAnimations() {
  animations.forEach((controls) => {
    if (typeof controls.stop === "function") controls.stop();
  });
  animations = [];
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function hold(ctx, ms) {
  let end = performance.now() + ms;
  while (performance.now() < end) {
    if (!ctx.alive()) return false;
    if (ctx.paused()) {
      await wait(120);
      end += 120;
      continue;
    }
    await wait(Math.min(120, Math.max(0, end - performance.now())));
  }
  return ctx.alive();
}

function move(el, frame, options = {}) {
  play(el, {
    left: frame.x,
    top: frame.y,
    width: frame.w,
    height: frame.h,
  }, { ...SPRING, ...options });
}

function setHud(view, keys, label, instant = false) {
  view.hudKeys.innerHTML = keys
    .map((key, index) => `${index > 0 ? '<span class="demo-key-plus">+</span>' : ""}<kbd class="demo-key">${key}</kbd>`)
    .join("");
  view.hudLabel.textContent = label;

  if (!instant) {
    play(view.hudInner, { scale: [0.985, 1] }, { duration: 0.24, ease: EASE_OUT });
  }
}

function pulseKeys(view) {
  play(view.hudKeys, { scale: [1, 0.9, 1] }, { duration: 0.28, ease: "easeOut" });
}

function setCaption(view, text) {
  if (!view.caption) return;
  view.caption.textContent = text;
  play(view.caption, { opacity: [0.35, 1] }, { duration: 0.35, ease: "easeOut" });
}

function placeHighlight(view, index, instant) {
  const item = view.switcherItems[index];
  if (!item) return;

  const box = {
    width: item.offsetWidth,
    height: item.offsetHeight,
    x: item.offsetLeft,
    y: item.offsetTop,
  };

  view.highlight.style.width = `${box.width}px`;
  view.highlight.style.height = `${box.height}px`;

  if (instant) {
    view.highlight.style.transform = `translate(${box.x}px, ${box.y}px)`;
  } else {
    play(view.highlight, { x: box.x, y: box.y }, { duration: 0.24, ease: EASE_OUT });
  }
}

export function resetView(view) {
  cancelAnimations();

  WINDOW_ORDER.forEach((id) => {
    const { el } = view.windows[id];
    applyFrame(el, INITIAL[id]);
    el.style.transform = "";
  });
  setFocus(view, "browse");

  view.switcher.style.opacity = "0";
  view.switcher.style.transform = "";
  view.hud.style.opacity = "0";

  placeHighlight(view, SWITCHER_START, true);
  setHud(view, ["⌥", "1"], "居中到预设尺寸", true);

  if (view.caption) {
    view.caption.textContent = "按住 ⌥，用三个快捷键管理当前屏幕的窗口";
  }
}

async function playOnce(view, ctx) {
  setHud(view, ["⌥", "1"], "居中到预设尺寸");
  setCaption(view, "把聚焦窗口居中，并调整为预设大小");
  if (!(await hold(ctx, 800))) return false;

  pulseKeys(view);
  move(view.windows.browse.el, CENTERED);
  if (!(await hold(ctx, 1200))) return false;

  setHud(view, ["⌥", "·"], "收起窗口");
  setCaption(view, "其他窗口也居中，并调整为同样大小");
  if (!(await hold(ctx, 600))) return false;

  pulseKeys(view);
  const pile = pileFrames();
  WINDOW_ORDER.forEach((id) => move(view.windows[id].el, pile[id]));
  if (!(await hold(ctx, 1200))) return false;

  setHud(view, ["⌥", "·"], "展开堆叠");
  setCaption(view, "再按一次，按设定间距展开堆叠");
  if (!(await hold(ctx, 600))) return false;

  pulseKeys(view);
  const expanded = expandedFrames();
  WINDOW_ORDER.forEach((id) => move(view.windows[id].el, expanded[id]));
  if (!(await hold(ctx, 1200))) return false;

  setHud(view, ["⌥", "Tab"], "切换窗口");
  setCaption(view, "按住 ⌥ 再按 Tab，打开窗口列表");
  if (!(await hold(ctx, 500))) return false;

  pulseKeys(view);
  placeHighlight(view, SWITCHER_START, true);
  play(view.switcher, { opacity: [0, 1], y: [14, 0], scale: [0.97, 1] }, { duration: 0.34, ease: EASE_OUT });
  if (!(await hold(ctx, 700))) return false;

  setCaption(view, "连按 Tab，在三个窗口之间轮切");
  for (const index of SWITCHER_CYCLE) {
    pulseKeys(view);
    placeHighlight(view, index, false);
    if (!(await hold(ctx, 760))) return false;
  }

  setCaption(view, "松开 ⌥，切换到选中的窗口");
  play(view.switcher, { opacity: [1, 0], y: [0, 10], scale: [1, 0.98] }, { duration: 0.22, ease: "easeIn" });

  setFocus(view, WINDOW_ORDER[SWITCHER_COMMIT]);
  const target = view.windows[WINDOW_ORDER[SWITCHER_COMMIT]].el;
  play(target, { scale: [1, 1.012, 1] }, { duration: 0.4, ease: "easeOut" });

  return hold(ctx, 1100);
}

export async function runLoop(view, ctx) {
  resetView(view);
  play(view.canvas, { opacity: [0, 1] }, { duration: 0.45, ease: "easeOut" });
  play(view.hud, { opacity: [0, 1] }, { duration: 0.4, ease: "easeOut", delay: 0.1 });
  if (!(await hold(ctx, 550))) return;

  while (ctx.alive()) {
    if (!(await playOnce(view, ctx))) break;

    play(view.canvas, { opacity: [1, 0] }, { duration: 0.3, ease: "easeIn" });
    play(view.hud, { opacity: [1, 0] }, { duration: 0.3, ease: "easeIn" });
    if (!(await hold(ctx, 400))) break;

    resetView(view);
    play(view.canvas, { opacity: [0, 1] }, { duration: 0.45, ease: "easeOut" });
    play(view.hud, { opacity: [0, 1] }, { duration: 0.4, ease: "easeOut" });
    if (!(await hold(ctx, 600))) break;
  }
}

export function showStaticState(view) {
  cancelAnimations();

  const expanded = expandedFrames();
  WINDOW_ORDER.forEach((id) => {
    const { el } = view.windows[id];
    applyFrame(el, expanded[id]);
    el.style.transform = "";
  });
  setFocus(view, WINDOW_ORDER[SWITCHER_COMMIT]);

  view.switcher.style.opacity = "1";
  view.switcher.style.transform = "";
  view.hud.style.opacity = "1";

  placeHighlight(view, SWITCHER_COMMIT, true);
  setHud(view, ["⌥", "Tab"], "切换窗口", true);

  if (view.caption) {
    view.caption.textContent = "按住 ⌥ 连按 Tab，在窗口之间轮切";
  }
}
