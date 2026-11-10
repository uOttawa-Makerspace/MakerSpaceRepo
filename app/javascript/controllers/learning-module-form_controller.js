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

  toggleScorm() {
    if (!this.hasScormToggleTarget) return;
    const isScorm = this.scormToggleTarget.checked;
    this.setSection(this.scormSectionTarget, isScorm);
    this.setSection(this.regularSectionTarget, !isScorm);
  }

  setSection(section, active) {
    section.style.display = active ? "" : "none";
    section.disabled = !active;
  }
}
