// Runs the handler on each Turbo page load, but only when the page contains
// the given root element. Scripts loaded by one page stay registered for the
// rest of the session, so without this they run (and throw) on every later page.
export function onPageLoad(rootSelector, handler) {
  document.addEventListener("turbo:load", (event) => {
    if (!document.querySelector(rootSelector)) return;
    return handler(event);
  });
}
