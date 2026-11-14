import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

// The supervisor and department lists of the key request form and wizard.
function nameSearch(id) {
  const select = document.getElementById(id);
  if (!select) return;
  tomSelectFor(select, {
    searchField: ["name"],
    valueField: "id",
    labelField: "name",
    maxOptions: null,
    searchOnKeyUp: true,
  });
}

onEveryPageLoad(() => {
  nameSearch("supervisor-select");
  nameSearch("space-select");
});
