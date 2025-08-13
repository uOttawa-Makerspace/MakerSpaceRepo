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
