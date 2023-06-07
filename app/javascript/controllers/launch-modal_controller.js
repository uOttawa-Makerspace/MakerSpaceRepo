import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["id", "title"];
  id = null;
  url = null;
  name = null;
  modal = null;
  title = null;

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
      this.idTargets.forEach((idTarget) => {
        idTarget.innerText = data.id;
      });
    }
    if (this.hasTitleTarget) {
      this.titleTargets.forEach((titleTarget) => {
        titleTarget.innerText = data.title;
      });
    }
  }

  async open() {
    await fetch(this.url)
      .then((r) => r.text())
      .then((html) => {
        const fragment = document.createRange().createContextualFragment(html);
        document.getElementById(`${this.name}-body`).appendChild(fragment);
      });
    document.body.classList.add("modal-open");
    this.modal.setAttribute("style", "display: block;");
    this.modal.classList.add("show");

    const modalBackdrop = document.createElement("div");
    modalBackdrop.classList.add("modal-backdrop");
    modalBackdrop.classList.add("fade");
    modalBackdrop.classList.add("show");
    modalBackdrop.id = "modal-backdrop";
    document.body.append(modalBackdrop);
  }

  close() {
    document.body.classList.remove("modal-open");
    this.modal.removeAttribute("style");
    this.modal.classList.remove("show");
    document.getElementsByClassName("modal-backdrop")[0].remove();
    document
      .getElementById(`${this.name}-body`)
      .removeChild(document.getElementById(`${this.name}-modal-rendered`));
  }
}
