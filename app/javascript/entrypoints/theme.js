import Cookies from "js-cookie";

document.addEventListener("turbo:load", () => {
  let themeToggler = document.querySelector("#themeToggler");

  // Test theme, set default to dark for release
  let prevTheme = Cookies.get("theme");
  if (!prevTheme) {
    document.documentElement.dataset.bsTheme = "dark";
  }

  themeToggler.addEventListener("click", () => {
    let currentTheme = document.documentElement.dataset.bsTheme || prevTheme;
    if (currentTheme == "dark") {
      document.documentElement.dataset.bsTheme = "light";
    } else {
      document.documentElement.dataset.bsTheme = "dark";
    }
    Cookies.set("theme", document.documentElement.dataset.bsTheme);
  });
});
