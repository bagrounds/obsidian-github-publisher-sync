export const findElementById = (nothing) => (just) => (id) => () => {
  if (typeof document === "undefined") return nothing;
  const found = document.getElementById(id);
  return found === null ? nothing : just(found);
};

export const createElementInDocument = (tag) => () =>
  document.createElement(tag);

export const createTextNodeInDocument = (value) => () =>
  document.createTextNode(value);

export const setAttributeOnElement = (name) => (value) => (node) => () => {
  node.setAttribute(name, value);
};

export const setStyleOnElement = (property) => (value) => (node) => () => {
  node.style.setProperty(property, value);
};

export const attachClickListener = (node) => (handler) => () => {
  node.addEventListener("click", () => handler());
};

export const attachCheckboxChangeListener = (node) => (handler) => () => {
  node.addEventListener("change", (event) => {
    const checked = !!(event && event.target && event.target.checked);
    handler(checked)();
  });
};

export const appendChildToElement = (parent) => (child) => () => {
  parent.appendChild(child);
};

export const removeAllChildrenFromElement = (node) => () => {
  while (node.firstChild) node.removeChild(node.firstChild);
};

// Stable identity must be drawn from a kebab-case alphabet so the
// attribute-selector in `restoreScrollPositions` can never become a
// vector for selector injection (every Word Meter testid in `View.purs`
// already conforms to this pattern). Entries that fail the check are
// skipped rather than silently round-tripped through an unsafe selector.
const safeTestidPattern = /^[a-z0-9-]+$/;

// Capture the scroll offsets of every testid-bearing descendant that has
// been scrolled away from the origin. The new DOM tree is regenerated from
// scratch on every dispatch, so without this any element with
// `overflow: auto` would silently snap back to (0, 0) every time the model
// changes. Using `data-testid` as stable identity reuses an existing
// convention without forcing the view layer to opt elements in one by one.
export const captureScrollPositions = (host) => () => {
  // An empty array (not null) is the canonical "no scrolled elements"
  // snapshot — it is truthy and zero-length, so `restoreScrollPositions`
  // simply iterates nothing.
  if (!host || typeof host.querySelectorAll !== "function") return [];
  const positions = [];
  const elements = host.querySelectorAll("[data-testid]");
  for (let i = 0; i < elements.length; i++) {
    const element = elements[i];
    const testid = element.getAttribute("data-testid");
    if (!testid || !safeTestidPattern.test(testid)) continue;
    const scrollTop = element.scrollTop || 0;
    const scrollLeft = element.scrollLeft || 0;
    if (scrollTop === 0 && scrollLeft === 0) continue;
    positions.push({ testid, scrollTop, scrollLeft });
  }
  return positions;
};

export const restoreScrollPositions = (host) => (snapshot) => () => {
  if (!host || typeof host.querySelector !== "function" || !snapshot) return;
  for (let i = 0; i < snapshot.length; i++) {
    const entry = snapshot[i];
    // Defense in depth: `captureScrollPositions` already filters to
    // kebab-case testids, but re-check here so a future caller cannot
    // smuggle an attacker-controlled string into the attribute selector.
    if (!safeTestidPattern.test(entry.testid)) continue;
    const match = host.querySelector(`[data-testid="${entry.testid}"]`);
    if (!match) continue;
    match.scrollTop = entry.scrollTop;
    match.scrollLeft = entry.scrollLeft;
  }
};

export const ensureStylesheetLinked = (defaultHref) => () => {
  if (typeof document === "undefined") return;
  const marker = "data-word-meter-stylesheet";
  // Derive the stylesheet URL from the currently-executing script so the
  // bundle works both in production (served from `/static/`) and in the
  // e2e fixture (served from `/quartz/static/`).
  const filename = "word-meter.css";
  const currentScript = document.currentScript;
  const href =
    currentScript && currentScript.src
      ? currentScript.src.replace(/[^/]+$/, filename)
      : defaultHref;
  if (
    document.querySelector &&
    document.querySelector(`link[${marker}="${href}"]`)
  )
    return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  link.setAttribute(marker, href);
  const parent = document.head || document.body;
  if (parent && parent.appendChild) parent.appendChild(link);
};
