import TomSelect from "tom-select";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("contact_info_space_id")) {
    if (!document.getElementById("contact_info_space_id").tomselect) {
      new TomSelect("#contact_info_space_id", {
        plugins: ["remove_button", "restore_on_backspace", "clear_button"],
        create: true,
        persist: false,
      });
    }
  }

  function attachToggleEvents(inputs) {
    inputs.forEach((fields) => {
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
  }
  // Attach events to what's already on the page
  attachToggleEvents(document.querySelectorAll("fieldset[data-toggled-by]"));

  document.querySelector("#addNewOpeningHour").addEventListener("click", () => {
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
      next_index
    );
    // Show clone
    template.hidden = false;
    document.querySelector("#openingHours").appendChild(template);
    // Attach events to the new form
    attachToggleEvents(template.querySelectorAll("fieldset[data-toggled-by]"));
  });
});
