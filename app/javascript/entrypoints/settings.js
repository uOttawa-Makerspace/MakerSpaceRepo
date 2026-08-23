import TomSelect from "tom-select";

let programTomSelect = null;

function initializeProgramSelect() {
  const programSelect = document.getElementById("user_program");
  if (!programSelect) return;

  if (programSelect.tomselect) {
    programSelect.tomselect.destroy();
  }

  const optgroups = Array.from(programSelect.querySelectorAll("optgroup"));

  programTomSelect = new TomSelect(programSelect, {
    maxItems: 1,
    maxOptions: null,
    searchOnKeyUp: true,
  });

  const facultySelect = document.getElementById("user_faculty");
  if (facultySelect) {
    facultySelect.addEventListener("change", () => {
      programSelect.querySelectorAll("optgroup").forEach((e) => e.remove());
      const targetLabel = facultySelect.value;

      optgroups.forEach((option) => {
        if (option.getAttribute("label") === targetLabel) {
          programSelect.appendChild(option.cloneNode(true));
        }
      });

      if (programSelect.tomselect) {
        programSelect.tomselect.clear();
        programSelect.tomselect.clearOptions();
        programSelect.tomselect.sync();
      }
    });
  }
}

document.addEventListener("turbo:load", initializeProgramSelect);
document.addEventListener("turbo:before-cache", () => {
  const programSelect = document.getElementById("user_program");
  if (programSelect?.tomselect) {
    programSelect.tomselect.destroy();
  }
});
