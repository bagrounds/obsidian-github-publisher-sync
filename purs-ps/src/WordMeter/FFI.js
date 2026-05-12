// FFI for WordMeter.FFI.
//
// We keep these functions intentionally tiny — one DOM call each — so
// that the PureScript side can compose them through capability
// instances later without leaking imperative cleverness into the JS.

export const getElementByIdImpl = (just) => (nothing) => (id) => () => {
  const element = typeof document === "undefined" ? null : document.getElementById(id);
  return element === null ? nothing : just(element);
};

export const setInnerHtml = (element) => (html) => () => {
  element.innerHTML = html;
};
