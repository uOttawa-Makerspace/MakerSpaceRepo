// The elements already bound: a second load over the same page binds nothing
// twice. A page Turbo restores from its cache is a copy made of new elements,
// which are bound again.
const boundElements = new WeakSet();

// Runs bind on the element the first time it is given one; nothing when the
// element is missing or was bound before.
export function bindOnce(el, bind) {
  if (!el || boundElements.has(el)) return;
  boundElements.add(el);
  bind(el);
}
