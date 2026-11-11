/* Common helper attributes for form elements */

document.addEventListener("turbo:load", function () {
  // Hide and show fields based on checked value of button
  /** @type {NodeListOf<HTMLInputElement>} */ (
    document.querySelectorAll("[data-toggles]")
  ).forEach((optionElement) => {
    // When a button changes value
    optionElement.addEventListener("change", function () {
      // Get all elements to hide if checked
      document
        .querySelectorAll(optionElement.dataset.toggles)
        .forEach((target) => {
          target.toggleAttribute("hidden", !optionElement.checked);
        });
    });

    optionElement.dispatchEvent(new Event("change"));
  });

  document.querySelectorAll("[data-show]").forEach((optionElement) => {
    optionElement.addEventListener("change", function () {
      document
        .querySelectorAll(optionElement.dataset.show)
        .forEach((target) => {
          target.hidden = !optionElement.checked;
        });
    });

    optionElement.dispatchEvent(new Event("change"));
  });

  document.querySelectorAll("[data-hide]").forEach((optionElement) => {
    optionElement.addEventListener("change", function () {
      document
        .querySelectorAll(optionElement.dataset.hide)
        .forEach((target) => {
          target.hidden = optionElement.checked;
        });
    });

    optionElement.dispatchEvent(new Event("change"));
  });

  document
    .querySelectorAll("[data-disable-on-select]")
    .forEach((optionElement) => {
      optionElement.addEventListener("change", function () {
        document
          .querySelectorAll(optionElement.dataset.disableOnSelect)
          .forEach((target) => {
            target.disabled = optionElement.checked;
          });
      });
    });

  document
    .querySelectorAll("[data-enable-on-select]")
    .forEach((optionElement) => {
      optionElement.addEventListener("change", function () {
        document
          .querySelectorAll(optionElement.dataset.enableOnSelect)
          .forEach((target) => {
            target.disabled = !optionElement.checked;
          });
      });
    });
});
