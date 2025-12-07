// Make a div containing a preview image and a hidden input
function appendFileToPreview(file, previewContainer) {
  console.log(file);
  // Create preview wrapper
  const preview = document.createElement("div");
  preview.classList.add("file-upload-item-preview");

  const previewImage = document.createElement("img");
  previewImage.src = URL.createObjectURL(file);
  preview.appendChild(previewImage);

  const previewInput = document.createElement("input");
  previewInput.type = "file";
  previewInput.hidden = true;
  const dataTransfer = new DataTransfer();
  dataTransfer.items.add(file);
  previewInput.files = dataTransfer.files;
  previewInput.name = `repository[photos_attributes][${Date.now()}][image]`;
  preview.append(previewInput);

  const previewDelete = document.createElement("button");
  previewDelete.addEventListener("click", (evt) => {
    preview.remove();
    evt.preventDefault;
  });
  previewDelete.role = "button"; // Prevent form submit
  previewDelete.classList.add("btn");
  previewDelete.classList.add("btn-danger");
  previewDelete.innerHTML = "<i class='fa fa-remove'></i> Delete";
  preview.append(previewDelete);

  previewContainer.appendChild(preview);
}

// Called when file input receives new files
function onFileUpload(evt) {
  const input = evt.currentTarget;
  const previewContainer = document.querySelector("[data-file-upload-preview]");
  // Create a preview element for each file
  Array.from(input.files).forEach((file) => {
    appendFileToPreview(file, previewContainer);
  });

  // Clear input
  input.value = null;
}

document.addEventListener("turbo:load", function () {
  document
    .querySelectorAll("input[type=file][data-file-upload-helper]")
    .forEach((el) => {
      el.addEventListener("change", onFileUpload);
    });
});
