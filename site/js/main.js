import { initHero } from "./hero.js";
import { initNav, initReveal } from "./reveal.js";
import { initDemo } from "./demo/index.js";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

initNav();
initDemo({ reducedMotion });
initReveal({ reducedMotion });
initHero({ reducedMotion });
