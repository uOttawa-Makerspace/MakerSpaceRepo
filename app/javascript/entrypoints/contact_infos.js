import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

// A fieldset is disabled while any of the checkboxes it names is checked.
const bindToggledFieldset = oncePerElement((fields) => {
  // Fieldset gives checkboxes to listen to
  fields.dataset.toggledBy.split(" ").forEach((checkid) => {
    // Get the checkbox
    let check = document.querySelector(checkid);
    if (check) {
      check.addEventListener("change", () => {
        // Update the field
        fields.disabled = check.checked;
      });
      check.dispatchEvent(new Event("change"));
    }
  });
});

function attachToggleEvents(inputs) {
  inputs.forEach(bindToggledFieldset);
}

// The add button of the opening hours: each click adds an empty opening hour
// form, copied from the hidden template.
const bindAddOpeningHour = oncePerElement((addNewOpeningHourButton) =>
  addNewOpeningHourButton.addEventListener("click", () => {
    let template = document
      .querySelector("#newOpeningHourSubForm")
      .cloneNode(true); // Deep clone
    template.id = "";
    let next_index =
      document.querySelector("#openingHours").childElementCount - 1;
    next_index = next_index < 0 ? 0 : next_index; // make sure it's not negative
    // Replace the array index
    template.innerHTML = template.innerHTML.replaceAll(
      "CHILDINDEX",
      next_index,
    );
    // Clear cloned form
    template.querySelectorAll("input").forEach((i) => {
      i.value = "";
    });
    // Show clone
    template.hidden = false;
    document.querySelector("#openingHours").appendChild(template);
    // Attach events to the new form
    attachToggleEvents(template.querySelectorAll("fieldset[data-toggled-by]"));
  }),
);

onEveryPageLoad(() => {
  const space = document.getElementById("contact_info_space_id");
  if (space) {
    tomSelectFor(space, {
      plugins: ["remove_button", "restore_on_backspace", "clear_button"],
      create: true,
      persist: false,
    });
  }

  // Attach events to what's already on the page
  attachToggleEvents(document.querySelectorAll("fieldset[data-toggled-by]"));
  bindAddOpeningHour(document.querySelector("#addNewOpeningHour"));
});
