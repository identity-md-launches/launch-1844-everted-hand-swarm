const NS = "http://www.w3.org/2000/svg";
/** Small deterministic 2D gradient noise; no rendering library or canvas. */
export function noise(x, y) {
  const ix = Math.floor(x),
    iy = Math.floor(y),
    fx = x - ix,
    fy = y - iy;
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  const grad = (a, b, dx, dy) => {
    const angle =
      (((Math.imul(a, 374761393) ^ Math.imul(b, 668265263)) >>> 0) % 6283) /
      1000;
    return Math.cos(angle) * dx + Math.sin(angle) * dy;
  };
  const u = fade(fx),
    v = fade(fy),
    lerp = (a, b, t) => a + (b - a) * t;
  return lerp(
    lerp(grad(ix, iy, fx, fy), grad(ix + 1, iy, fx - 1, fy), u),
    lerp(grad(ix, iy + 1, fx, fy - 1), grad(ix + 1, iy + 1, fx - 1, fy - 1), u),
    v,
  );
}

/** @param {(key:string) => any} t */
export function createSwarm(t) {
  const area = /** @type {HTMLElement} */ (
    document.querySelector("#playground")
  );
  const svg = /** @type {SVGSVGElement} */ (document.querySelector("#swarm"));
  const seal = /** @type {HTMLButtonElement} */ (
    document.querySelector("#logo-sticker")
  );
  const counter = document.querySelector("#sprout-count");
  const lore = document.querySelector("#lore");
  const pause = document.querySelector("#motion-toggle");
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  /** @type {{g:SVGGElement,x:number,y:number,seed:number,angle:number}[]} */
  const hands = [];
  let count = 0,
    paused = false,
    visible = true,
    frame = 0,
    clock = 0,
    lastTime = 0,
    drag = null,
    dx = 0,
    dy = 0,
    moved = false;
  function renderCount() {
    counter.textContent = t(count === 1 ? "countOne" : "count").replace(
      "{n}",
      String(count),
    );
  }
  function add(x, y, interactive = true) {
    if (hands.length >= 28) {
      lore.textContent = t("countLimit");
      return;
    }
    const index = hands.length;
    const g = document.createElementNS(NS, "g");
    const use = document.createElementNS(NS, "use");
    use.setAttribute("href", "assets/hand.svg#swarm-hand");
    use.setAttribute("width", "76");
    use.setAttribute("height", "100");
    g.append(use);
    const hand = {
      g,
      x: Math.max(5, Math.min(510, x)),
      y: Math.max(10, Math.min(420, y)),
      seed: index * 7.3 + 0.47,
      angle: ((index * 47) % 70) - 35,
    };
    g.setAttribute(
      "transform",
      `translate(${hand.x} ${hand.y}) rotate(${hand.angle} 38 50)`,
    );
    g.addEventListener("pointerenter", () => {
      use.style.filter = "invert(1)";
    });
    g.addEventListener("pointerleave", () => {
      use.style.filter = "";
    });
    g.addEventListener("click", (event) => {
      event.stopPropagation();
      add(hand.x + 40, hand.y + 20);
    });
    svg.append(g);
    hands.push(hand);
    if (interactive) {
      count++;
      renderCount();
      const bites = t("lore");
      lore.textContent = bites[(count - 1) % bites.length];
      if (!reduced.matches && !paused) {
        const circle = document.createElementNS(NS, "circle");
        circle.setAttribute("cx", String(hand.x + 38));
        circle.setAttribute("cy", String(hand.y + 50));
        circle.setAttribute("r", "4");
        circle.setAttribute("fill", "none");
        circle.setAttribute("stroke", "#e7e1df");
        circle.classList.add("swarm-ripple");
        svg.append(circle);
        setTimeout(() => circle.remove(), 700);
      }
    }
  }
  function sprout() {
    const angle = count * 2.399963;
    add(260 + Math.cos(angle) * 215, 210 + Math.sin(angle) * 180);
  }
  function reset() {
    svg.replaceChildren();
    hands.length = 0;
    count = 0;
    dx = 0;
    dy = 0;
    seal.style.setProperty("--dx", "0px");
    seal.style.setProperty("--dy", "0px");
    [
      [65, 65],
      [445, 90],
      [40, 330],
      [450, 360],
      [255, 15],
    ].forEach(([x, y]) => add(x, y, false));
    renderCount();
  }
  function tick(time) {
    frame = 0;
    if (paused || reduced.matches || !visible || document.hidden) {
      lastTime = 0;
      return;
    }
    if (lastTime) clock += Math.min(time - lastTime, 40) / 6000;
    lastTime = time;
    for (const h of hands) {
      const x = h.x + noise(clock + h.seed, h.seed) * 20;
      const y = h.y + noise(h.seed, clock + h.seed) * 16;
      h.g.setAttribute(
        "transform",
        `translate(${x.toFixed(2)} ${y.toFixed(2)}) rotate(${h.angle + noise(clock, h.seed) * 8} 38 50)`,
      );
    }
    frame = requestAnimationFrame(tick);
  }
  function syncMotion() {
    const stopped = paused || reduced.matches;
    /** @type {HTMLButtonElement} */ (pause).disabled = reduced.matches;
    document.documentElement.dataset.motion = stopped ? "paused" : "running";
    pause.setAttribute("aria-pressed", String(stopped));
    pause.setAttribute("aria-label", t(reduced.matches ? "motionReduced" : stopped ? "resume" : "pause"));
    pause.textContent = stopped ? "▷" : "Ⅱ";
    if (!frame && !stopped) frame = requestAnimationFrame(tick);
  }
  pause.addEventListener("click", () => {
    // System reduced-motion remains authoritative; it is never overridden by a click.
    paused = !paused;
    syncMotion();
  });
  reduced.addEventListener("change", syncMotion);
  document.addEventListener("visibilitychange", syncMotion);
  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    syncMotion();
  }).observe(area);
  document.querySelector("#sprout").addEventListener("click", sprout);
  document.querySelector("#reset-swarm").addEventListener("click", () => {
    reset();
    lore.textContent = t("resetMessage");
  });
  area.addEventListener("click", (event) => {
    if (event.target !== area && event.target !== svg) return;
    const box = area.getBoundingClientRect();
    add(
      ((event.clientX - box.left) / box.width) * 600 - 38,
      ((event.clientY - box.top) / box.height) * 550 - 50,
    );
  });
  seal.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    drag = { x: event.clientX, y: event.clientY, dx, dy };
    moved = false;
    seal.setPointerCapture(event.pointerId);
  });
  function position(x, y) {
    const max = area.clientWidth * 0.16;
    dx = Math.min(max, Math.max(-max, x));
    dy = Math.min(max, Math.max(-max, y));
    seal.style.setProperty("--dx", `${dx}px`);
    seal.style.setProperty("--dy", `${dy}px`);
  }
  seal.addEventListener("pointermove", (event) => {
    if (!drag) return;
    const x = event.clientX - drag.x,
      y = event.clientY - drag.y;
    if (Math.abs(x) + Math.abs(y) > 6) moved = true;
    position(drag.dx + x, drag.dy + y);
  });
  seal.addEventListener("pointerup", () => {
    drag = null;
  });
  seal.addEventListener("pointercancel", () => {
    drag = null;
    moved = true;
  });
  seal.addEventListener("click", () => {
    if (!moved) sprout();
    moved = false;
  });
  seal.addEventListener("keydown", (event) => {
    const keys = {
      ArrowLeft: [-12, 0],
      ArrowRight: [12, 0],
      ArrowUp: [0, -12],
      ArrowDown: [0, 12],
    };
    if (keys[event.key]) {
      event.preventDefault();
      position(dx + keys[event.key][0], dy + keys[event.key][1]);
    }
    if (event.key === "Home") {
      event.preventDefault();
      position(0, 0);
    }
  });
  reset();
  syncMotion();
  return {
    translate() {
      renderCount();
      syncMotion();
      lore.textContent = "";
    },
  };
}
