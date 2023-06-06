import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["title"];
  id = null;
  title = null;

  setCoHostContent(data) {
    this.titleTarget.innerHTML = data.title;
    this.id = data.id;
    this.title = data.title;
  }

  async open() {
    await fetch(`/proficient_projects/${this.id}/proficient_project_modal/`)
      .then((r) => r.text())
      .then((html) => {
        const fragment = document.createRange().createContextualFragment(html);
        document
          .getElementById("proficient-project-body")
          .appendChild(fragment);
      });
    document.body.classList.add("modal-open");
    this.element.setAttribute("style", "display: block;");
    this.element.classList.add("show");

    const modalBackdrop = document.createElement("div");
    modalBackdrop.classList.add("modal-backdrop");
    modalBackdrop.classList.add("fade");
    modalBackdrop.classList.add("show");
    modalBackdrop.id = "modal-backdrop";
    document.body.append(modalBackdrop);
  }

  close() {
    document.body.classList.remove("modal-open");
    this.element.removeAttribute("style");
    this.element.classList.remove("show");
    document.getElementsByClassName("modal-backdrop")[0].remove();
    document
      .getElementById("proficient-project-body")
      .removeChild(
        document.getElementById("proficient-project-modal-rendered")
      );
  }
}
