import { animate, inView } from "./motion.js";

const EASE_OUT = [0.22, 1, 0.36, 1];

export function initNav() {
  const nav = document.querySelector("[data-nav]");
  const sentinel = document.querySelector("[data-nav-sentinel]");
  if (!nav || !sentinel) return;

  const observer = new IntersectionObserver(([entry]) => {
    nav.dataset.scrolled = String(!entry.isIntersecting);
  }, { rootMargin: "-4px 0px 0px 0px" });

  observer.observe(sentinel);
}

export function initReveal({ reducedMotion }) {
  if (reducedMotion) return;

  document.querySelectorAll("[data-reveal-group]").forEach((group) => {
    const items = Array.from(group.querySelectorAll("[data-reveal-item]"));
    if (items.length === 0) return;

    items.forEach((item) => {
      item.style.opacity = "0";
      item.style.transform = "translateY(18px)";
    });

    let shown = false;
    inView(group, () => {
      if (shown) return;
      shown = true;
      items.forEach((item, index) => {
        animate(item, { opacity: [0, 1], y: [18, 0] }, {
          duration: 0.65,
          delay: index * 0.07,
          ease: EASE_OUT,
        });
      });
    }, { margin: "0px 0px -12% 0px" });
  });
}
