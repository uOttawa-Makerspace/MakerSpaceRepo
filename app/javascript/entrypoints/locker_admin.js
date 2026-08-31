// app/javascript/locker_admin.js
document.addEventListener("turbo:load", () => {
  // Initialize Bootstrap tooltips for the notes hover bubbles
  const tooltipTriggerList = document.querySelectorAll(
    '[data-bs-toggle="tooltip"]',
  );
  if (tooltipTriggerList.length > 0) {
    tooltipTriggerList.forEach((el) => new bootstrap.Tooltip(el));
  }

  // Inline editing toggle logic
  const editToggle = document.getElementById("lockerEditToggle");
  if (editToggle) {
    editToggle.addEventListener("change", function () {
      // Target both inline edits and the variant size selects
      const inlineFields = document.querySelectorAll(
        ".locker-inline-edit, .locker-variant-select",
      );
      inlineFields.forEach((field) => {
        field.disabled = !this.checked;
      });
    });
  }

  // Indefinite checkbox logic
  const indefiniteCheckboxes = document.querySelectorAll(
    "input[data-indefinite-target]",
  );
  indefiniteCheckboxes.forEach((check) => {
    const targetId = check.dataset.indefiniteTarget;
    const target = document.getElementById(targetId);

    if (target) {
      // Set initial state
      target.disabled = check.checked;

      check.addEventListener("change", function () {
        target.disabled = this.checked;
        if (this.checked) target.value = "";
      });
    }
  });
});
