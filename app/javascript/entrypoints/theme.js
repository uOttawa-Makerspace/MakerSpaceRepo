import Cookies from "js-cookie";
// import { Tooltip } from "bootstrap";

document.addEventListener("turbo:load", () => {
  let themeToggler = document.querySelector("#themeToggler");
  // let themeTooltip = new Tooltip(themeToggler);

  function isTodayHalloween() {
    let d = new Date();
    // Oct 31 2025
    // months start from 0
    return d.getFullYear() == 2025 && d.getMonth() == 9 && d.getDate() == 31;
  }

  // Test theme, set default to dark for release
  let prevTheme = Cookies.get("theme");
  if (!prevTheme && isTodayHalloween()) {
    document.documentElement.dataset.bsTheme = "dark";
    // Check visibility, tooltip shows at top corner on mobile
    // Show tooltip
    // themeTooltip.show();
    // setTimeout(() => {
    //   themeTooltip.hide();
    // }, 4000);
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
