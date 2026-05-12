export const findElementByIdImpl = (nothing) => (just) => (id) => () => {
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

export const appendChildToElement = (parent) => (child) => () => {
  parent.appendChild(child)
}

export const removeAllChildrenFromElement = (node) => () => {
  while (node.firstChild) node.removeChild(node.firstChild)
}
