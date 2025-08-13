// FILE INPUT FORM
document.addEventListener("DOMContentLoaded", () => {
  const fileInputContainer = document.getElementById("file-input-container");
  const newFileInputTemplate = document.getElementById("new-file-input");
  const addFileButton = document.getElementById("add-file-button");
  const required =
    fileInputContainer.querySelector('input[type="file"]').required;

  function updateDeleteButtons() {
    const inputs = fileInputContainer.querySelectorAll(".upload-file-input");
    inputs.forEach((div, index) => {
      const deleteBtn = div.querySelector(".delete-file-button");
      if (deleteBtn) {
        deleteBtn.style.display =
          required && inputs.length === 1 ? "none" : "inline-block";
      }
    });
  }

  function addDeleteEvent(button) {
    button.addEventListener("click", (e) => {
      const allInputs =
        fileInputContainer.querySelectorAll(".upload-file-input");
      if (required && allInputs.length === 1) return;
      e.target.closest(".upload-file-input").remove();
      updateDeleteButtons();
    });
  }

  // Setup existing delete buttons
  fileInputContainer
    .querySelectorAll(".delete-file-button")
    .forEach(addDeleteEvent);

  addFileButton.addEventListener("click", () => {
    const clone = newFileInputTemplate.cloneNode(true);
    clone.removeAttribute("id");
    clone.style.display = "flex";

    const input = clone.querySelector('input[type="file"]');
    input.required = false;
    input.multiple = false;
    input.value = "";

    const deleteBtn = clone.querySelector(".delete-file-button");
    addDeleteEvent(deleteBtn);

    fileInputContainer.appendChild(clone);
    updateDeleteButtons();
  });

  updateDeleteButtons();
});

// HANDLE INITAL SERVICE SELECTION
document.addEventListener("DOMContentLoaded", () => {
  const accordionButtons = document.querySelectorAll(".accordion-button");
  const radioButtons = document.querySelectorAll(".service-radio");

  radioButtons.forEach((radio) => {
    radio.addEventListener("change", () => {
      const serviceGroup = radio.dataset.serviceGroup;

      // Highlight the selected accordion header
      accordionButtons.forEach((btn) => {
        btn.classList.remove("text-primary", "fw-bold");
        const desc = btn.querySelector("p");
        if (desc) desc.classList.remove("text-primary");
        if (desc) desc.classList.add("text-muted");
      });

      const selectedHeader = document.querySelector(
        `.accordion-button[data-service-group="${serviceGroup}"]`,
      );
      if (selectedHeader) {
        selectedHeader.classList.add("text-primary", "fw-bold");
        const desc = selectedHeader.querySelector("p");
        if (desc) {
          desc.classList.add("text-primary");
          desc.classList.remove("text-muted");
        }
      }

      // Clear inputs when custom is selected
      if (radio.value === "custom") {
        document.querySelectorAll(".service-name-field").forEach((field) => {
          if (field.dataset.serviceGroupId !== serviceGroup) {
            field.value = "";
          }
        });
      }
    });
  });

  // Init selected state
  const initiallySelectedRadio = document.querySelector(
    ".service-radio:checked",
  );
  if (initiallySelectedRadio) {
    const serviceGroup = initiallySelectedRadio.dataset.serviceGroup;
    const selectedHeader = document.querySelector(
      `.accordion-button[data-service-group="${serviceGroup}"]`,
    );
    if (selectedHeader) {
      selectedHeader.classList.add("text-primary", "fw-bold");
      const desc = selectedHeader.querySelector("p");
      if (desc) {
        desc.classList.add("text-primary");
        desc.classList.remove("text-muted");
      }
    }
  }
});
