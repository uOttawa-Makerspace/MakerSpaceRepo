import TomSelect from "tom-select";
import { tomSelectOptions } from "./page_locale.js";

let programTomSelect = null;

// The faculty selects already given their change listener: a second load over
// the same page adds none. A page Turbo restores from its cache is a copy made
// of new elements, which are bound again.
const filteredFaculties = new WeakSet();

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

  const facultySelect = document.getElementById("user_faculty");
  if (facultySelect && !filteredFaculties.has(facultySelect)) {
    filteredFaculties.add(facultySelect);
    facultySelect.addEventListener("change", () =>
      showProgramsOf(facultySelect.value, programSelect, optgroups),
    );
  }
}

// Leaves in the program select only the programs of the chosen faculty.
function showProgramsOf(faculty, programSelect, optgroups) {
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
