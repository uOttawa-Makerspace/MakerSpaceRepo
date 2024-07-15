import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  const programSelect = document.getElementById("user_program");
  if (programSelect && !programSelect.tomselect) {
    new TomSelect(programSelect, {
      maxItems: 1,
      maxOptions: null,
      searchOnKeyUp: true,
    });

    // this is a non-live NodeList, we store it for later use
    const optgroups = Array.from(programSelect.querySelectorAll("optgroup"));
    const facultySelect = document.getElementById("user_faculty");
    if (facultySelect) {
      facultySelect.addEventListener("change", function () {
        // https://tom-select.js.org/docs/api/
        programSelect.querySelectorAll("optgroup").forEach((e) => e.remove());
        // Add allowed programs
        let target_label = facultySelect.value;
        for (let i = 0; i < optgroups.length; i++) {
          let option = optgroups[i];
          if (option.getAttribute("label") == target_label)
            programSelect.appendChild(option);
        }

        programSelect.tomselect.clear();
        programSelect.tomselect.clearOptions();
        programSelect.tomselect.sync();
      });
    }
  }
});
