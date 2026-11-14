import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";

document.addEventListener("turbo:load", () => {
  const spaceManagerSelect = document.getElementById("space-manager-select");
  if (spaceManagerSelect && !spaceManagerSelect.tomselect) {
    new TomSelect(
      "#space-manager-select",
      tomSelectOptions(document, {
        searchField: ["name"],
        valueField: "id",
        labelField: "name",
        maxOptions: null,
        searchOnKeyUp: true,
      }),
    );
  }
});
