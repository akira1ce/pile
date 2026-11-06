import { buildStage, fitStage } from "./stage.js";
import { resetView, runLoop, showStaticState } from "./timeline.js";

export function initDemo({ reducedMotion }) {
  const stage = document.querySelector("[data-demo-stage]");
  if (!stage) return;

  const view = buildStage(stage);
  fitStage(stage);

  if (reducedMotion) {
    showStaticState(view);
    return;
  }

  let visible = false;
  let hovered = false;
  let generation = 0;

  const start = () => {
    if (!visible) return;
    const current = ++generation;
    runLoop(view, {
      alive: () => current === generation && visible && !document.hidden,
      paused: () => hovered,
    }).catch((error) => {
      console.error("pile demo:", error);
    });
  };

  const stop = () => {
    generation += 1;
    resetView(view);
  };

  const observer = new IntersectionObserver(([entry]) => {
    const next = entry.isIntersecting;
    if (next === visible) return;
    visible = next;
    if (visible) start();
    else stop();
  }, { threshold: 0.3 });
  observer.observe(stage);

  stage.addEventListener("mouseenter", () => {
    hovered = true;
  });
  stage.addEventListener("mouseleave", () => {
    hovered = false;
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stop();
    else if (visible) start();
  });
}
