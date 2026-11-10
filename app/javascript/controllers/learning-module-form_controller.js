import { Controller } from "@hotwired/stimulus";

// Behaviour of the new/edit learning module form. It reads and changes only
// the form it is attached to, so it works however the page was reached.
export default class extends Controller {
  static targets = [
    "photos",
    "saveButton",
    "scormToggle",
    "scormSection",
    "regularSection",
  ];
  static values = { photosRequired: Boolean };

  connect() {
    this.toggleScorm();
  }

  submit(event) {
    if (this.photosRequiredValue && this.photosMissing()) {
      this.rejectMissingPhotos(event);
    } else if (this.element.checkValidity()) {
      this.showSaving();
    }
  }

  // Clone the photo input row, turning the + button into a remove button
  addPhoto(event) {
    const row = event.currentTarget.parentElement;
    const clone = row.cloneNode(true);

    const input = clone.querySelector('input[type="file"]');
    input.value = null;
    input.removeAttribute("data-learning-module-form-target");

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

  // Photos live in the regular files section, which is disabled (and so not
  // submitted) for a SCORM module.
  photosMissing() {
    return (
      !this.regularSectionTarget.disabled && this.photosTarget.files.length < 1
    );
  }

  rejectMissingPhotos(event) {
    const photos = this.photosTarget;
    event.preventDefault();
    event.stopPropagation();
    photos.focus();
    if (photos.parentElement.querySelector(".invalid-feedback")) return;
    photos.classList.add("is-invalid");
    const feedback = document.createElement("div");
    feedback.classList.add("invalid-feedback", "text-center");
    feedback.textContent = "You must upload at least one image";
    photos.parentNode.appendChild(feedback);
  }

  showSaving() {
    if (!this.hasSaveButtonTarget) return;
    // Allow a small timeout so the form submit event fires cleanly
    setTimeout(() => {
      this.saveButtonTarget.disabled = true;
      this.saveButtonTarget.innerHTML =
        '<i class="fa fa-spinner fa-spin me-1"></i> Saving (Please wait)...';
    }, 0);
  }
}
