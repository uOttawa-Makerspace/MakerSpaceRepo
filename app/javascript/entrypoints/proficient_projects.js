import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import { addInputRow } from "../src/input_rows.js";
import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { pageTable } from "../src/page_table.js";
// Colours each status button by its status.
function colourStatusButton(element) {
  if (element.innerHTML === "Revoked") {
    element.classList.add("btn-danger");
  } else if (element.innerHTML === "Awarded") {
    element.classList.add("btn-success");
  } else {
    element.classList.add("btn-warning");
  }
}

// The project form is not sent without at least one image, uploaded before or
// chosen now.
const bindImageCheck = oncePerElement((form) => {
  form.addEventListener("submit", (e) => {
    let images = document.getElementById("images_");
    let image_feedback = document.createElement("div");
    image_feedback.classList.add("text-center");
    let uploaded_images = document.getElementsByClassName("image-item").length;
    let total_images = uploaded_images + images.files.length;
    if (total_images < 1) {
      e.preventDefault();
      e.stopPropagation();
      document.getElementById("files_").focus();
      if (!images.parentElement.querySelector(".invalid-feedback")) {
        images.classList.add("is-invalid");
        image_feedback.classList.add("invalid-feedback");
        if (total_images < 1) {
          image_feedback.innerHTML = "Please upload at least one image";
          images.parentElement.appendChild(image_feedback);
        }
      }
    }
  });
});

// A saved file's remove link marks it for deletion and takes it off the list.
const bindFileRemove = oncePerElement((el) => {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    document.getElementById("deletefiles").value += el.id + ",";
    el.parentElement.parentElement.remove();
  });
});

// A saved image's remove link marks it for deletion and takes it off the list.
const bindImageRemove = oncePerElement((el) => {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    document.getElementById("deleteimages").value += el.id + ",";
    el.parentElement.remove();
  });
});

// The add button of a file or photo input: each click adds another input row
// with a button that removes it.
const bindAddInputRow = oncePerElement((addButton) =>
  addButton.addEventListener("click", () => addInputRow(addButton)),
);

// The remove buttons of the added input rows, listened to on the rows' parent,
// so the rows of a page Turbo restores from its cache can be removed too.
const bindRemoveInputRow = oncePerElement((rows) =>
  rows.addEventListener("click", (event) => {
    const remove = event.target.closest(".input-group > .btn-danger");
    if (remove && rows.contains(remove)) remove.parentElement.remove();
  }),
);

function bindInputRows(addButton) {
  bindAddInputRow(addButton);
  bindRemoveInputRow(addButton?.parentElement.parentElement);
}

function buildTrainingPicker() {
  const select = document.getElementById("training_requirements");
  if (!select || select.tomselect) return;
  new TomSelect(
    "#training_requirements",
    tomSelectOptions(document, {
      plugins: ["remove_button"],
      maxItems: null,
    }),
  );
}

onEveryPageLoad(() => {
  [...document.getElementsByClassName("pp-status-button")].forEach(
    colourStatusButton,
  );
  buildTrainingPicker();
  bindImageCheck(
    document.getElementById("new_proficient_project") ||
      document.getElementsByClassName("edit_proficient_project")[0],
  );
  [...document.getElementsByClassName("file-remove")].forEach(bindFileRemove);
  [...document.getElementsByClassName("image-remove")].forEach(bindImageRemove);
  bindInputRows(document.getElementById("new-file-input"));
  bindInputRows(document.getElementById("new-photo-input"));
});

// The delete buttons of the training requirement rows, listened to on the
// rows' parent, so the rows of a page Turbo restores from its cache can be
// deleted too.
const bindRequirementDelete = oncePerElement((rows) =>
  rows.addEventListener("click", (event) => {
    const remove = event.target.closest(".tr-delete-button");
    if (remove && rows.contains(remove)) remove.parentNode.remove();
  }),
);

// The new requirement button adds an empty copy of the requirement row.
const bindNewRequirement = oncePerElement((newTr) => {
  newTr.addEventListener("click", () => {
    const clone = document.getElementById("new-link-input").cloneNode(true);
    document.getElementById("link-container").append(clone);
    clone.removeAttribute("id");
    clone.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
    clone.style.visibility = "visible";
  });
});

onEveryPageLoad(() => {
  bindRequirementDelete(document.getElementById("link-container"));
  bindNewRequirement(document.getElementById("new-tr"));
});

onEveryPageLoad(() => {
  pageTable(document.getElementById("prof-proj-requests"));
});
