/* Makerepo file upload utility. Attaches to a file upload input and provides an
 * editable preview pane. Developed with the repository upload/edit page in
 * mind. See docs for more info */

// Use Date.now() as the starting counter to guarantee no collision with
// Rails form-builder indices (0, 1, 2…) for pre-existing records.
let counter = Date.now();
function getNextCounter() {
  return counter++;
}

// Make a div containing a preview image and a hidden input
function appendFileToPreview(file, previewContainer, fieldPrefix, fieldSuffix) {
  // Create preview wrapper
  const preview = document.createElement("div");
  preview.classList.add("file-upload-item-preview");

  const previewImage = document.createElement("img");
  const objectURL = URL.createObjectURL(file);
  // If image errors out, this isn't something we can preview.
  previewImage.addEventListener("error", (evt) => {
    URL.revokeObjectURL(objectURL);
    evt.currentTarget.removeAttribute("src");
  });
  previewImage.addEventListener("load", () => {
    URL.revokeObjectURL(objectURL);
  });
  previewImage.src = objectURL;
  preview.appendChild(previewImage);

  const previewFilename = document.createElement("span");
  previewFilename.textContent = file.name;
  preview.appendChild(previewFilename);

  const previewInput = document.createElement("input");
  previewInput.type = "file";
  previewInput.hidden = true;
  const dataTransfer = new DataTransfer();
  dataTransfer.items.add(file);
  previewInput.files = dataTransfer.files;
  previewInput.name = `${fieldPrefix}[${getNextCounter()}]`;
  // Append an extra attribute if needed. This is because of workarounds how
  // files and image are attached to repos via a model indirection. Annoying
  if (fieldSuffix) {
    previewInput.name += `[${fieldSuffix}]`;
  }
  preview.append(previewInput);

  // For non-persisted files this is a button
  const previewDelete = document.createElement("button");
  previewDelete.textContent = "Delete";
  previewDelete.classList.add("file-upload-item-delete");
  previewDelete.type = "button"; // Prevent form submit
  previewDelete.addEventListener("click", (evt) => {
    // Remove parent preview container
    preview.remove();
    evt.preventDefault();
  });
  preview.append(previewDelete);

  previewContainer.appendChild(preview);
}

// Called when file input receives new files
function onFileUpload(evt) {
  const input = evt.currentTarget;
  const previewContainer = document.querySelector(
    input.dataset.fileUploadPreviewSelector,
  );

  const fileUploadLimit = parseInt(input.dataset.fileUploadLimit, 10);
  // Count files currently candidates for upload
  const currentFileCount = previewContainer.querySelectorAll(
    ".file-upload-item-preview:not([hidden])",
  ).length;
  // Create a preview element for each file
  Array.from(input.files).forEach((file, index) => {
    // if the limit is undefined, or total count is less than limit
    if (!fileUploadLimit || index + currentFileCount < fileUploadLimit) {
      appendFileToPreview(
        file,
        previewContainer,
        input.dataset.fileUploadPrefix,
        input.dataset.fileUploadSuffix,
      );
    }
  });

  // Clear input
  input.value = null;
}

function createFileInput(target) {
  // Guard against re-initialization on repeated turbo:load events
  if (target.dataset.fileUploadInitialized) return;
  target.dataset.fileUploadInitialized = "true";

  // Attach change handlers
  target.addEventListener("change", onFileUpload);
  // Copy name as a prefix
  target.dataset.fileUploadPrefix = target.name;
  // Clear name, we don't want to submit this input anymore
  target.removeAttribute("name");

  // For pre-existing preview boxes attach a delete handler to the checkboxes
  const preview = document.querySelector(
    target.dataset.fileUploadPreviewSelector,
  );

  if (!preview) {
    throw new Error(
      "Preview pane not found or not specified, file upload helper cannot function without a place to store hidden file inputs.",
    );
  }

  // Find preview boxes under the target
  const previewBoxes = preview.querySelectorAll(".file-upload-item-preview");

  previewBoxes.forEach((previewBox) => {
    const deleteBtn = previewBox.querySelector(
      "[data-file-upload-item-delete]",
    );
    const destroyInput = previewBox.querySelector(
      "[data-file-upload-hidden-destroy]",
    );

    if (deleteBtn && destroyInput) {
      deleteBtn.addEventListener("click", () => {
        // We have to submit the _destroy flag to server, hide preview instead
        previewBox.hidden = true;
        destroyInput.value = true;
      });
    }
  });
}

document.addEventListener("turbo:load", function () {
  document
    .querySelectorAll("input[type=file][data-file-upload-helper]")
    .forEach((el) => {
      createFileInput(el);
    });
});
