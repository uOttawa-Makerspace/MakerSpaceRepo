/* Makerepo file upload utility. Attaches to a file upload input and provides an
 * editable preview pane. Developed with the repository upload/edit page in
 * mind. See docs for more info */

// TODO: This probably doesn't work for one-file uploads, due to appending the
// ID to each preview.
//
// TODO: Drag and drop spaces
// FIXME: What happens if no preview pane is found?

// Rails requires arrays to be assigned an index for
// accepts_nested_attributes_for to work with pre-existing files. Date.now() is
// in milliseconds resolution and my dev machine is fast enough to get duplicate
// indices.
let counter = 1;
function getNextCounter() {
  counter += 1;
  return counter;
}

// Make a div containing a preview image and a hidden input
function appendFileToPreview(file, previewContainer, fieldPrefix, fieldSuffix) {
  // Create preview wrapper
  const preview = document.createElement("div");
  preview.classList.add("file-upload-item-preview");

  const previewImage = document.createElement("img");
  // If image errors out, this isn't something we can preview.
  previewImage.addEventListener("error", (evt) => {
    evt.currentTarget.removeAttribute("src");
  });
  previewImage.src = URL.createObjectURL(file);
  preview.appendChild(previewImage);

  const previewFilename = document.createElement("span");
  previewFilename.innerText = file.name;
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
  previewDelete.innerHTML = "Delete";
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

  const fileUploadLimit = parseInt(input.dataset.fileUploadLimit);
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
    // Find delete buttons inside each preview box
    previewBox
      .querySelector("[data-file-upload-item-delete]")
      .addEventListener("click", () => {
        // We have to submit the _destroy flag to server, hide preview instead
        previewBox.hidden = true;
        previewBox.querySelector("[data-file-upload-hidden-destroy]").value =
          true;
      });
  });
}

document.addEventListener("turbo:load", function () {
  document
    .querySelectorAll("input[type=file][data-file-upload-helper]")
    .forEach((el) => {
      createFileInput(el);
    });
});
