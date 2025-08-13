import { Controller } from "@hotwired/stimulus";
import { Modal } from "bootstrap";

export default class extends Controller {
  static targets = ["id", "title"];

  id = null;
  url = null;
  name = null;
  modal = null;
  title = null;
  bootstrapModal = null;

  openModal(event) {
    this.setCoHostContent(event.currentTarget.dataset);
    this.open();
  }

  setCoHostContent(data) {
    this.id = data.id;
    this.title = data.title;
    this.url = data.url;
    this.name = data.name;
    this.modal = document.getElementById(`${this.name}-modal`);

    if (this.hasIdTarget) {
      this.idTargets.forEach((idTarget) => (idTarget.innerText = data.id));
    }
    if (this.hasTitleTarget) {
      this.titleTargets.forEach(
        (titleTarget) => (titleTarget.innerText = data.title),
      );
    }
  }

  async open() {
    const body = document.getElementById(`${this.name}-body`);
    body.innerHTML = ""; // clear previous content
    const html = await fetch(this.url).then((r) => r.text());
    const fragment = document.createRange().createContextualFragment(html);
    body.appendChild(fragment);

    // Create and show native Bootstrap modal instance
    this.bootstrapModal = Modal.getOrCreateInstance(this.modal);
    this.bootstrapModal.show();
  }

  close() {
    if (!this.name) {
      this.name = this.element.id.replace("-modal", "");
    }
    if (!this.modal) {
      this.modal = this.element;
    }

    if (this.bootstrapModal) {
      this.bootstrapModal.hide();
    } else {
      const instance = Modal.getInstance(this.modal);
      if (instance) instance.hide();
    }
  }
}
