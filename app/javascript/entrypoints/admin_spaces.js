import { tomSelectFor } from "../src/tom_select.js";

document.addEventListener("turbo:load", () => {
  const spaceManagerSelect = document.getElementById("space-manager-select");
  if (spaceManagerSelect) {
    tomSelectFor(spaceManagerSelect, {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
});
