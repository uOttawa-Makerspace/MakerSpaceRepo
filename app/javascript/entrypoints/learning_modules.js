import Sortable from "sortablejs";
import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  document.querySelectorAll("[data-order]").forEach((reorderSwitch) => {
    // Find order container
    const modules = document.querySelector(
      `[data-order-container='${reorderSwitch.dataset.order}']`,
    );
    // Attach sortable
    let sortable = new Sortable(modules, {
      sort: reorderSwitch.checked,
      handle: ".sort-handle",
      onEnd: (e) => {
        fetch("/learning_area/reorder", {
          method: "PUT",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            data: [...e.from.children].map((c) => c.dataset.id),
            format: "json",
          }),
        }).catch((error) => console.error("Reorder failed:", error.message));
      },
    });

    reorderSwitch.addEventListener("change", (ev) => {
      sortable.option("sort", ev.currentTarget.checked);
      modules
        .querySelectorAll(".sort-handle")
        .forEach((el) => (el.hidden = !ev.currentTarget.checked));
    });
  });

  let subskill = document.querySelector("#learning_module_subskill");
  if (subskill) {
    new TomSelect(subskill, {
      maxItems: 1,
      plugins: ["remove_button"],
      create: true,
    });
  }
});

// Only validate photo presence on new records, not edit
const form = document.getElementById("new_learning_module");
if (form) {
  form.addEventListener("submit", (e) => {
    const photos = document.getElementById("learning_module_photos");
    if (photos.files.length < 1) {
      e.preventDefault();
      e.stopPropagation();
      photos.focus();
      if (!photos.parentElement.querySelector(".invalid-feedback")) {
        photos.classList.add("is-invalid");
        const feedback = document.createElement("div");
        feedback.classList.add("invalid-feedback", "text-center");
        feedback.textContent = "You must upload at least one image";
        photos.parentNode.appendChild(feedback);
      }
    }
  });
}

// Clone photo input row, turning the + button into a remove button on the clone
const newPhotoBtn = document.getElementById("new-photo-input");
if (newPhotoBtn) {
  newPhotoBtn.addEventListener("click", () => {
    const parent = newPhotoBtn.parentElement;
    const clone = parent.cloneNode(true);

    clone.querySelector('input[type="file"]').value = null;

    const cloneBtn = clone.querySelector("button");
    cloneBtn.removeAttribute("id");
    cloneBtn.className = "btn btn-danger";
    cloneBtn.querySelector("i").className = "fa fa-trash";
    cloneBtn.addEventListener("click", () => clone.remove());

    parent.parentElement.appendChild(clone);
  });
}

// Remove button deletes the whole image-item div
document.querySelectorAll(".image-remove").forEach((btn) => {
  btn.addEventListener("click", () => {
    btn.closest(".image-item").remove();
  });
});

// Remove existing video — drops signed_id from submission
document.querySelectorAll(".video-remove").forEach((btn) => {
  btn.addEventListener("click", () => btn.closest(".video-item").remove());
});

const toggle = document.querySelector("#learning_module_scorm_enabled");
const scormSection = document.querySelector("fieldset#scorm-section");
const regularSection = document.querySelector("fieldset#regular-files-section");

if (toggle) {
  const applyScormToggle = () => {
    const isScorm = toggle.checked;
    scormSection.style.display = isScorm ? "" : "none";
    scormSection.disabled = !isScorm;

    regularSection.style.display = isScorm ? "none" : "";
    regularSection.disabled = isScorm;
  };

  toggle.addEventListener("change", applyScormToggle);
  applyScormToggle();
}
