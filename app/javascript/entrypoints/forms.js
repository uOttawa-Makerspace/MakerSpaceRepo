/* Common helper attributes for form elements */

document.addEventListener("turbo:load", function () {
  // Hide and show fields based on checked value of button
  document.querySelectorAll("[data-toggles]").forEach((optionElement) => {
    // When a button changes value
    optionElement.addEventListener("change", function () {
      // Get all elements to hide if checked
      document
        .querySelectorAll(optionElement.currentTarget.dataset.toggles)
        .forEach((target) => {
          target.hidden = !optionElement.currentTarget.checked;
          console.log(target.hidden);
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
});
