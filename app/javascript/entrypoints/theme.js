import Cookies from "js-cookie";

// Apply theme BEFORE Turbo renders (prevents flicker during navigation)
document.addEventListener("turbo:before-render", (event) => {
  const savedTheme = Cookies.get("theme") || "dark";
  event.detail.newBody.parentElement.dataset.bsTheme = savedTheme;
});

// Initialize theme on page load
document.addEventListener("turbo:load", () => {
  const themeToggler = document.querySelector("#themeToggler");

  // Apply saved theme or default to dark
  const savedTheme = Cookies.get("theme") || "dark";
  document.documentElement.dataset.bsTheme = savedTheme;

  // Toggle theme on click
  themeToggler.addEventListener("click", () => {
    const currentTheme = document.documentElement.dataset.bsTheme;
    const newTheme = currentTheme === "dark" ? "light" : "dark";

    document.documentElement.dataset.bsTheme = newTheme;
    Cookies.set("theme", newTheme, { expires: 365, sameSite: "lax" });
  });
});

// Apply theme immediately on first page load
(function () {
  const savedTheme = Cookies.get("theme") || "dark";
  document.documentElement.dataset.bsTheme = savedTheme;
})();
