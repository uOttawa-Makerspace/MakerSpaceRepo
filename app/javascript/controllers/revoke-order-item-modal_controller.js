import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["id"];
  id = null;

  setCoHostContent(data) {
    this.idTarget.innerHTML = data.id;
    this.id = data.id;
  }

  async open() {
    await fetch(`/order_items/${this.id}/revoke_order_item_modal`)
      .then((r) => r.text())
      .then((html) => {
        const fragment = document.createRange().createContextualFragment(html);
        document.getElementById("revoke-order-item-body").appendChild(fragment);
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
      .getElementById("revoke-order-item-body")
      .removeChild(document.getElementById("revoke-order-item-modal-rendered"));
  }
}
