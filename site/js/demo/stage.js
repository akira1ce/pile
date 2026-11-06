import { INITIAL, STAGE, WINDOW_ORDER, WINDOW_TITLES } from "./layouts.js";

const ICONS = {
  browse: `
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="8.5"/>
      <path d="M3.5 12h17M12 3.5c2.4 2.2 3.6 5 3.6 8.5S14.4 18.3 12 20.5C9.6 18.3 8.4 15.5 8.4 12S9.6 5.7 12 3.5Z"/>
    </svg>`,
  notes: `
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M6 3.5h8L19 8v12.5H6z"/>
      <path d="M14 3.5V8h5M9 12h7M9 15.5h7"/>
    </svg>`,
  files: `
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M3.5 7.5h6l1.8 2h9.2v9.5H3.5z"/>
      <path d="M3.5 7.5V5h6l1.8 2"/>
    </svg>`,
};

const BODIES = {
  files: `
    <div class="demo-body demo-body--files">
      <div class="demo-sidebar">
        <span class="demo-nav-row is-active"></span>
        <span class="demo-nav-row"></span>
        <span class="demo-nav-row"></span>
        <span class="demo-nav-row"></span>
      </div>
      <div class="demo-list">
        <span class="demo-list-row"><i></i><b></b></span>
        <span class="demo-list-row"><i></i><b></b></span>
        <span class="demo-list-row"><i></i><b></b></span>
        <span class="demo-list-row"><i></i><b></b></span>
        <span class="demo-list-row"><i></i><b></b></span>
        <span class="demo-list-row"><i></i><b></b></span>
      </div>
    </div>`,
  notes: `
    <div class="demo-body demo-body--notes">
      <span class="demo-note-title"></span>
      <span class="demo-note-line" style="width: 92%"></span>
      <span class="demo-note-line" style="width: 84%"></span>
      <span class="demo-note-line" style="width: 88%"></span>
      <span class="demo-note-line" style="width: 64%"></span>
      <span class="demo-note-line" style="width: 90%"></span>
      <span class="demo-note-line" style="width: 76%"></span>
      <span class="demo-note-line" style="width: 86%"></span>
    </div>`,
  browse: `
    <div class="demo-body demo-body--browse">
      <div class="demo-toolbar">
        <span class="demo-tool-glyph"></span>
        <span class="demo-tool-glyph"></span>
        <span class="demo-address"></span>
      </div>
      <div class="demo-browse-hero"></div>
      <div class="demo-browse-row"><span></span><span></span><span></span></div>
    </div>`,
};

const FOCUSED_Z = 40;

export function applyFrame(el, frame) {
  el.style.left = `${frame.x}px`;
  el.style.top = `${frame.y}px`;
  el.style.width = `${frame.w}px`;
  el.style.height = `${frame.h}px`;
  el.style.zIndex = String(frame.z);
}

export function setFocus(view, id) {
  WINDOW_ORDER.forEach((wid) => {
    const { el } = view.windows[wid];
    const focused = wid === id;
    el.classList.toggle("is-focused", focused);
    el.style.zIndex = String(focused ? FOCUSED_Z : INITIAL[wid].z);
  });
}

export function buildStage(stage) {
  const canvas = stage.querySelector("[data-demo-canvas]");
  canvas.replaceChildren();

  const windows = {};
  WINDOW_ORDER.forEach((id) => {
    const el = document.createElement("div");
    el.className = `demo-window demo-window--${id}`;
    el.innerHTML = `
      <div class="demo-titlebar">
        <span class="demo-lights"><i class="demo-traffic"></i><i class="demo-traffic"></i><i class="demo-traffic"></i></span>
        <span class="demo-title">${WINDOW_TITLES[id]}</span>
      </div>
      ${BODIES[id]}
    `;
    applyFrame(el, INITIAL[id]);
    canvas.append(el);
    windows[id] = { id, el };
  });

  const switcher = document.createElement("div");
  switcher.className = "demo-switcher";
  switcher.innerHTML = `
    <div class="demo-switcher-highlight"></div>
    ${WINDOW_ORDER.map((id) => `
      <div class="demo-switcher-item">
        <span class="demo-switcher-icon">${ICONS[id]}</span>
        <span class="demo-switcher-caption">${WINDOW_TITLES[id]}</span>
      </div>`).join("")}
  `;
  canvas.append(switcher);

  const switcherWidth = switcher.offsetWidth;
  const switcherHeight = switcher.offsetHeight;
  switcher.style.left = `${(STAGE.width - switcherWidth) / 2}px`;
  switcher.style.top = `${(STAGE.height - switcherHeight) / 2}px`;
  switcher.style.opacity = "0";

  const hud = document.createElement("div");
  hud.className = "demo-hud";
  hud.innerHTML = `
    <div class="demo-hud-inner">
      <span class="demo-keys"></span>
      <span class="demo-hud-label"></span>
    </div>
  `;
  canvas.append(hud);

  const highlight = switcher.querySelector(".demo-switcher-highlight");

  return {
    canvas,
    windows,
    switcher,
    switcherItems: Array.from(switcher.querySelectorAll(".demo-switcher-item")),
    highlight,
    hud,
    hudInner: hud.querySelector(".demo-hud-inner"),
    hudKeys: hud.querySelector(".demo-keys"),
    hudLabel: hud.querySelector(".demo-hud-label"),
    caption: document.querySelector("[data-demo-caption]"),
  };
}

export function fitStage(stage) {
  const update = () => {
    stage.style.setProperty("--stage-scale", String(stage.clientWidth / STAGE.width));
  };

  update();
  new ResizeObserver(update).observe(stage);
}
