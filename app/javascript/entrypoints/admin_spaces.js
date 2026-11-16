import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

onEveryPageLoad(() => {
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
