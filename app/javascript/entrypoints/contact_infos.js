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

  document.querySelectorAll("fieldset[data-toggled-by]").forEach((fields) => {
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
});
