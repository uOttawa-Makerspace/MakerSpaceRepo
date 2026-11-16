const pending = new Map();

// Adds a classic script to the page once per URL and resolves when it has run.
// Rejects when the browser cannot fetch or run it (blocked, offline, slow host
// timing out); a later call then tries again.
export function loadScript(src, attributes = {}) {
  if (pending.has(src)) return pending.get(src);
  const promise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.async = true;
    Object.entries(attributes).forEach(([name, value]) =>
      script.setAttribute(name, value),
    );
    script.addEventListener("load", () => resolve(script));
    script.addEventListener("error", () => {
      script.remove();
      pending.delete(src);
      reject(new Error(`Could not load ${src}`));
    });
    document.head.appendChild(script);
  });
  pending.set(src, promise);
  return promise;
}

// Runs the callback once the page and its own resources have finished loading,
// so a slow third-party host never delays what the visitor came to see.
export function afterPageLoad(callback) {
  if (document.readyState === "complete") {
    callback();
    return () => {};
  }
  window.addEventListener("load", callback, { once: true });
  return () => window.removeEventListener("load", callback);
}
