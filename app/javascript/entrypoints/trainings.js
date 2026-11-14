import DataTable from "datatables.net-bs5";
import { dataTableOptions } from "../src/page_locale.js";
import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

// The skill pickers of the training form, in English and in French; each
// select names its remove button (data-remove-title).
function skillPicker(id) {
  const select = /** @type {HTMLSelectElement} */ (document.getElementById(id));
  if (!select) return;
  tomSelectFor(select, {
    sortField: "text",
    create: true,
    plugins: ["remove_button"],
    persist: false,
  });
}

onEveryPageLoad(() => {
  skillPicker("training_list_of_skills_en");
  skillPicker("training_list_of_skills_fr");
});

document.addEventListener("turbo:load", () => {
  new DataTable("#trainings-table", dataTableOptions(document));
});
