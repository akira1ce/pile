import { animate, scroll } from "./motion.js";

const EASE_OUT = [0.22, 1, 0.36, 1];

export function initHero({ reducedMotion }) {
  const hero = document.querySelector("[data-hero]");
  if (!hero) return;

  const items = Array.from(hero.querySelectorAll("[data-hero-item]"));
  if (!reducedMotion && items.length > 0) {
    items.forEach((item) => {
      item.style.opacity = "0";
      item.style.transform = "translateY(14px)";
    });
    items.forEach((item, index) => {
      animate(item, { opacity: [0, 1], y: [14, 0] }, {
        duration: 0.75,
        delay: 0.06 + index * 0.08,
        ease: EASE_OUT,
      });
    });
  }

  const frame = document.querySelector("[data-stage-frame]");
  if (!frame || reducedMotion) return;

  const drift = animate(frame, { y: [24, -24] }, { ease: "linear" });
  try {
    scroll(drift, { target: frame, offset: ["start end", "end start"] });
  } catch (error) {
    drift.stop();
    frame.style.transform = "";
    console.warn("pile: scroll animation unavailable", error);
  }
}
