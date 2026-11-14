import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";

let supervisorSelect = document.getElementById("supervisor-select");
if (supervisorSelect && !supervisorSelect.tomselect) {
  new TomSelect(
    "#supervisor-select",
    tomSelectOptions(document, {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    }),
  );
}

let spaceSelect = document.getElementById("space-select");
if (spaceSelect && !spaceSelect.tomselect) {
  new TomSelect(
    "#space-select",
    tomSelectOptions(document, {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    }),
  );
}
