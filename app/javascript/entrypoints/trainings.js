import TomSelect from "tom-select";
import DataTable from "datatables.net-bs5";
import { dataTableOptions, tomSelectOptions } from "../src/page_locale.js";

// The skill pickers of the training form, in English and in French; each
// select names its remove button (data-remove-title).
function skillPicker(id) {
  const select = /** @type {HTMLSelectElement} */ (document.getElementById(id));
  if (!select) return;
  new TomSelect(
    select,
    tomSelectOptions(select, {
      sortField: "text",
      create: true,
      plugins: ["remove_button"],
      persist: false,
    }),
  );
}

document.addEventListener("turbo:load", () => {
  skillPicker("training_list_of_skills_en");
  skillPicker("training_list_of_skills_fr");
});

document.addEventListener("turbo:load", () => {
  new DataTable("#trainings-table", dataTableOptions(document));
});
