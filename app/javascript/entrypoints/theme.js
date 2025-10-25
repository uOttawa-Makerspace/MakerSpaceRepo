import Cookies from "js-cookie";

document.querySelector("#themeToggler").addEventListener("click", () => {
  let currentTheme = document.documentElement.dataset.bsTheme;
  if (currentTheme == "dark") {
    document.documentElement.dataset.bsTheme = "light";
  } else {
    document.documentElement.dataset.bsTheme = "dark";
  }
  Cookies.set("theme", document.documentElement.dataset.bsTheme);
});
