import Cookies from "js-cookie";

function getStoredTheme() {
  return (
    Cookies.get("theme") ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light")
  );
}

function applyTheme(theme) {
  document.documentElement.dataset.bsTheme = theme;
  // CRITICAL: path: "/" ensures the cookie is valid across all routes (/admin, /staff, etc.)
  Cookies.set("theme", theme, { expires: 365, sameSite: "lax", path: "/" });
}

export function toggleTheme() {
  const currentTheme =
    document.documentElement.dataset.bsTheme || getStoredTheme();
  const newTheme = currentTheme === "dark" ? "light" : "dark";
  applyTheme(newTheme);
}

// 1. Apply theme BEFORE Turbo renders to prevent dark/light flash during transitions
document.addEventListener("turbo:before-render", (event) => {
  const savedTheme = Cookies.get("theme") || "dark";
  if (event.detail.newBody?.parentElement) {
    event.detail.newBody.parentElement.dataset.bsTheme = savedTheme;
  }
});

// 2. Initialize and bind toggler on Turbo load
document.addEventListener("turbo:load", () => {
  const savedTheme = Cookies.get("theme") || "dark";
  document.documentElement.dataset.bsTheme = savedTheme;

  const themeToggler = document.querySelector("#themeToggler");
  if (themeToggler) {
    // Using .onclick prevents event listener stacking across Turbo visits
    themeToggler.onclick = (e) => {
      e.preventDefault();
      toggleTheme();
    };
  }
});

// 3. Apply theme immediately on initial script evaluation
(function () {
  const savedTheme = Cookies.get("theme") || "dark";
  document.documentElement.dataset.bsTheme = savedTheme;
})();

// Expose globally for any legacy HTML onclick triggers
window.toggleTheme = toggleTheme;
