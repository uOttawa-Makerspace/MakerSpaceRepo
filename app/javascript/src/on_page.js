// Runs the handler on each Turbo page load, but only when the page contains
// the given root element. Scripts loaded by one page stay registered for the
// rest of the session, so without this they run (and throw) on every later page.
export function onPageLoad(rootSelector, handler) {
  document.addEventListener("turbo:load", (event) => {
    if (!document.querySelector(rootSelector)) return;
    return handler(event);
  });
}

// Runs the setup over the page the script came with, then again on every
// later Turbo load and restore. Turbo can run a script it adds on a visit after
// that visit's turbo:load, so the first run does not wait for the event. On a
// full page load the setup runs twice over the same page, so it must leave an
// element it has already set up as it is (see oncePerElement, tomSelectFor).
export function onEveryPageLoad(setUp) {
  setUp();
  document.addEventListener("turbo:load", setUp);
}

// The bind function, run at most once per element: a second load over the same
// page binds nothing twice, and the new elements of a page Turbo restores from
// its cache are bound again. A missing element is skipped.
export function oncePerElement(bind) {
  const bound = new WeakSet();
  return (el) => {
    if (!el || bound.has(el)) return;
    bound.add(el);
    bind(el);
  };
}
