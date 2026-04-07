import Sortable from "sortablejs";

//  Unique index counter
let counter = Date.now();
function getNextCounter() {
  return counter++;
}

//
// POSITION TRACKING
//
function updatePositions(container) {
  container
    .querySelectorAll(".file-upload-item-preview:not([hidden])")
    .forEach((item, index) => {
      const input = item.querySelector("[data-file-upload-position]");
      if (input) input.value = index;
    });
}

//
// FILE TYPE CHECK
//
function isFileAccepted(file, accept) {
  if (!accept) return true;
  return accept
    .split(",")
    .map((t) => t.trim().toLowerCase())
    .some((type) => {
      if (type.startsWith(".")) return file.name.toLowerCase().endsWith(type);
      if (type.endsWith("/*"))
        return file.type.startsWith(type.replace("/*", "/"));
      return file.type === type;
    });
}

//
// BUILD A SINGLE PREVIEW ITEM
//
function appendFileToPreview(file, previewContainer, fieldPrefix, fieldSuffix) {
  const isSortable = previewContainer.hasAttribute("data-file-upload-sortable");

  const preview = document.createElement("div");
  preview.classList.add("file-upload-item-preview");

  //  Drag handle (sortable containers only)
  if (isSortable) {
    const handle = document.createElement("span");
    handle.classList.add("file-upload-drag-handle");
    handle.innerHTML = "&#x2630;";
    handle.title = "Drag to reorder";
    preview.appendChild(handle);
  }

  //  Thumbnail
  const img = document.createElement("img");
  const objectURL = URL.createObjectURL(file);
  img.addEventListener("error", (e) => {
    URL.revokeObjectURL(objectURL);
    const placeholder = document.createElement("div");
    placeholder.classList.add("file-upload-preview-failed");
    e.currentTarget.replaceWith(placeholder);
  });
  img.addEventListener("load", () => URL.revokeObjectURL(objectURL));
  img.src = objectURL;
  preview.appendChild(img);

  //  Filename
  const nameSpan = document.createElement("span");
  nameSpan.textContent = file.name;
  nameSpan.title = file.name;
  preview.appendChild(nameSpan);

  //  Hidden <input type="file"> carrying the actual blob
  const itemIndex = getNextCounter();
  const fileInput = document.createElement("input");
  fileInput.type = "file";
  fileInput.hidden = true;
  const dt = new DataTransfer();
  dt.items.add(file);
  fileInput.files = dt.files;
  fileInput.name = `${fieldPrefix}[${itemIndex}]`;
  if (fieldSuffix) fileInput.name += `[${fieldSuffix}]`;
  preview.appendChild(fileInput);

  //  Position hidden input (sortable containers only)
  if (isSortable) {
    const posInput = document.createElement("input");
    posInput.type = "hidden";
    posInput.name = `${fieldPrefix}[${itemIndex}][position]`;
    posInput.dataset.fileUploadPosition = "";
    posInput.value = "0";
    preview.appendChild(posInput);
  }

  //  Delete button
  const deleteBtn = document.createElement("button");
  deleteBtn.textContent = "Delete";
  deleteBtn.type = "button";
  deleteBtn.classList.add("file-upload-item-delete");
  deleteBtn.addEventListener("click", (e) => {
    e.preventDefault();
    preview.remove();
    if (isSortable) updatePositions(previewContainer);
  });
  preview.appendChild(deleteBtn);

  previewContainer.appendChild(preview);
  if (isSortable) updatePositions(previewContainer);
}

//
// FILE INPUT change HANDLER
//
function onFileUpload(evt) {
  const input = evt.currentTarget;
  const previewContainer = document.querySelector(
    input.dataset.fileUploadPreviewSelector,
  );
  const limit = parseInt(input.dataset.fileUploadLimit, 10);
  const current = previewContainer.querySelectorAll(
    ".file-upload-item-preview:not([hidden])",
  ).length;

  Array.from(input.files).forEach((file, i) => {
    if (!limit || i + current < limit) {
      appendFileToPreview(
        file,
        previewContainer,
        input.dataset.fileUploadPrefix,
        input.dataset.fileUploadSuffix,
      );
    }
  });

  input.value = null;
}

//
// SORTABLE (SortableJS)
//
function setupSortable(container) {
  // Add drag handles to any pre-existing server-rendered items
  container.querySelectorAll(".file-upload-item-preview").forEach((item) => {
    if (!item.querySelector(".file-upload-drag-handle")) {
      const handle = document.createElement("span");
      handle.classList.add("file-upload-drag-handle");
      handle.innerHTML = "&#x2630;";
      handle.title = "Drag to reorder";
      item.prepend(handle);
    }
  });

  Sortable.create(container, {
    animation: 150,
    handle: ".file-upload-drag-handle",
    ghostClass: "file-upload-dragging",
    chosenClass: "file-upload-chosen",
    dragClass: "file-upload-drag",
    filter: "[hidden]", // skip hidden (soft-deleted) items
    preventOnFilter: false,
    onEnd: () => updatePositions(container),
  });
}

//
// DROP ZONE
//
function setupDropZone(dropZone, fileInput) {
  const previewContainer = document.querySelector(
    fileInput.dataset.fileUploadPreviewSelector,
  );
  let enterCount = 0;

  dropZone.addEventListener("dragenter", (e) => {
    if (!e.dataTransfer.types.includes("Files")) return;
    e.preventDefault();
    enterCount++;
    dropZone.classList.add("file-upload-drop-active");
  });

  dropZone.addEventListener("dragover", (e) => {
    if (!e.dataTransfer.types.includes("Files")) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
  });

  dropZone.addEventListener("dragleave", (e) => {
    if (!e.dataTransfer.types.includes("Files")) return;
    enterCount--;
    if (enterCount <= 0) {
      enterCount = 0;
      dropZone.classList.remove("file-upload-drop-active");
    }
  });

  dropZone.addEventListener("drop", (e) => {
    if (!e.dataTransfer.files.length) return;
    e.preventDefault();
    e.stopPropagation();
    enterCount = 0;
    dropZone.classList.remove("file-upload-drop-active");

    const limit = parseInt(fileInput.dataset.fileUploadLimit, 10);
    const current = previewContainer.querySelectorAll(
      ".file-upload-item-preview:not([hidden])",
    ).length;
    const accept = fileInput.accept || "";

    Array.from(e.dataTransfer.files).forEach((file, i) => {
      if (accept && !isFileAccepted(file, accept)) return;
      if (!limit || i + current < limit) {
        appendFileToPreview(
          file,
          previewContainer,
          fileInput.dataset.fileUploadPrefix,
          fileInput.dataset.fileUploadSuffix,
        );
      }
    });
  });
}

//
// BOOTSTRAP
//
function createFileInput(target) {
  if (target.dataset.fileUploadInitialized) return;
  target.dataset.fileUploadInitialized = "true";

  target.dataset.fileUploadPrefix = target.name;
  target.removeAttribute("name");
  target.addEventListener("change", onFileUpload);

  const preview = document.querySelector(
    target.dataset.fileUploadPreviewSelector,
  );
  if (!preview) {
    throw new Error(
      "file_upload: preview pane not found for selector " +
        target.dataset.fileUploadPreviewSelector,
    );
  }

  //  Pre-existing items: hook up delete buttons
  preview.querySelectorAll(".file-upload-item-preview").forEach((box) => {
    const deleteBtn = box.querySelector("[data-file-upload-item-delete]");
    const destroyInput = box.querySelector("[data-file-upload-hidden-destroy]");
    if (deleteBtn && destroyInput) {
      deleteBtn.addEventListener("click", () => {
        box.hidden = true;
        destroyInput.value = true;
        if (preview.hasAttribute("data-file-upload-sortable")) {
          updatePositions(preview);
        }
      });
    }
  });

  //  Sortable reordering (gallery images)
  if (preview.hasAttribute("data-file-upload-sortable")) {
    setupSortable(preview);
    updatePositions(preview);
  }

  //  Drop zone
  const dropZone = target.closest(".file-upload-drop-zone");
  if (dropZone) {
    setupDropZone(dropZone, target);
  }
}

//
// ENTRY POINT
//
function init() {
  document
    .querySelectorAll("input[type=file][data-file-upload-helper]")
    .forEach((el) => createFileInput(el));
}

document.addEventListener("turbo:load", init);
if (document.readyState !== "loading") {
  init();
} else {
  document.addEventListener("DOMContentLoaded", init);
}
