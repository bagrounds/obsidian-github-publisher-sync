export const findElementById = (nothing) => (just) => (id) => () => {
  if (typeof document === "undefined") return nothing
  const found = document.getElementById(id)
  return found === null ? nothing : just(found)
}

export const createElementInDocument = (tag) => () => document.createElement(tag)

export const createTextNodeInDocument = (value) => () => document.createTextNode(value)

export const setAttributeOnElement = (name) => (value) => (node) => () => {
  node.setAttribute(name, value)
}

export const setStyleOnElement = (property) => (value) => (node) => () => {
  node.style.setProperty(property, value)
}

export const attachClickListener = (node) => (handler) => () => {
  node.addEventListener("click", () => handler())
}

export const attachCheckboxChangeListener = (node) => (handler) => () => {
  node.addEventListener("change", (event) => {
    const checked = !!(event && event.target && event.target.checked)
    handler(checked)()
  })
}

export const appendChildToElement = (parent) => (child) => () => {
  parent.appendChild(child)
}

export const removeAllChildrenFromElement = (node) => () => {
  while (node.firstChild) node.removeChild(node.firstChild)
}

export const ensureStylesheetLinked = (defaultHref) => () => {
  if (typeof document === "undefined") return
  const marker = "data-word-meter-stylesheet"
  // Derive the stylesheet URL from the currently-executing script so the
  // bundle works both in production (served from `/static/`) and in the
  // e2e fixture (served from `/quartz/static/`).
  const filename = "word-meter.css"
  const currentScript = document.currentScript
  const href = (currentScript && currentScript.src)
    ? currentScript.src.replace(/[^/]+$/, filename)
    : defaultHref
  if (document.querySelector && document.querySelector(`link[${marker}="${href}"]`)) return
  const link = document.createElement("link")
  link.rel = "stylesheet"
  link.href = href
  link.setAttribute(marker, href)
  const parent = document.head || document.body
  if (parent && parent.appendChild) parent.appendChild(link)
}
