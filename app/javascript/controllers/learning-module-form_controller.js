import { Controller } from "@hotwired/stimulus";

// Behaviour of the new/edit learning module form. It reads and changes only
// the form it is attached to, so it works however the page was reached.
export default class extends Controller {
  static targets = ["scormToggle", "scormSection", "regularSection"];

  connect() {
    this.toggleScorm();
  }

  // Clone the photo input row, turning the + button into a remove button
  addPhoto(event) {
    const row = event.currentTarget.parentElement;
    const clone = row.cloneNode(true);

    const input = clone.querySelector('input[type="file"]');
    input.value = null;

    const button = clone.querySelector("button");
    button.removeAttribute("id");
    button.className = "btn btn-danger";
    button.querySelector("i").className = "fa fa-trash";
    button.dataset.action = "learning-module-form#removePhotoRow";

    row.parentElement.appendChild(clone);
  }

  removePhotoRow(event) {
    event.currentTarget.parentElement.remove();
  }

  removeImage(event) {
    event.currentTarget.closest(".image-item").remove();
  }

  removeVideo(event) {
    event.currentTarget.closest(".video-item").remove();
  }

  // Targets are read through Stimulus' typed `targets` set rather than the
  // generated `...Target` getters, which the type checker cannot see.
  toggleScorm() {
    const toggle = /** @type {HTMLInputElement | null} */ (
      this.targets.find("scormToggle")
    );
    if (!toggle) return;
    const isScorm = toggle.checked;
    this.setSection(this.sectionTarget("scormSection"), isScorm);
    this.setSection(this.sectionTarget("regularSection"), !isScorm);
  }

  /** @param {string} name */
  sectionTarget(name) {
    return /** @type {HTMLFieldSetElement} */ (this.targets.find(name));
  }

  /**
   * @param {HTMLFieldSetElement} section
   * @param {boolean} active
   */
  setSection(section, active) {
    section.style.display = active ? "" : "none";
    section.disabled = !active;
  }
}
