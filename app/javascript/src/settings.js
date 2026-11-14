import TomSelect from "tom-select";
import { tomSelectOptions } from "./page_locale.js";
import { bindOnce } from "./bind_once.js";

let programTomSelect = null;

function initializeProgramSelect() {
  const programSelect = document.getElementById("user_program");
  if (!programSelect) return;

  if (programSelect.tomselect) {
    programSelect.tomselect.destroy();
  }

  const optgroups = Array.from(programSelect.querySelectorAll("optgroup"));

  programTomSelect = new TomSelect(
    programSelect,
    tomSelectOptions(programSelect, {
      maxItems: 1,
      maxOptions: null,
      searchOnKeyUp: true,
    }),
  );

  // The listener keeps the full program list of the first load of the page.
  bindOnce(document.getElementById("user_faculty"), (facultySelect) =>
    facultySelect.addEventListener(
      "change",
      showProgramsOf.bind(null, facultySelect, programSelect, optgroups),
    ),
  );
}

// Leaves in the program select only the programs of the chosen faculty.
function showProgramsOf(facultySelect, programSelect, optgroups) {
  const faculty = facultySelect.value;
  programSelect.querySelectorAll("optgroup").forEach((e) => e.remove());

  optgroups.forEach((option) => {
    if (option.getAttribute("label") === faculty) {
      programSelect.appendChild(option.cloneNode(true));
    }
  });

  if (programSelect.tomselect) {
    programSelect.tomselect.clear();
    programSelect.tomselect.clearOptions();
    programSelect.tomselect.sync();
  }
}

document.addEventListener("turbo:load", initializeProgramSelect);
document.addEventListener("turbo:before-cache", () => {
  const programSelect = document.getElementById("user_program");
  if (programSelect?.tomselect) {
    programSelect.tomselect.destroy();
  }
});
