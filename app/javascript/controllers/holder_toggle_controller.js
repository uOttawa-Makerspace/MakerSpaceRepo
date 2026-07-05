import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["internal", "external"];

  toggle(event) {
    const isExternal = event.target.value === "external";

    this.internalTarget.classList.toggle("d-none", isExternal);
    this.externalTarget.classList.toggle("d-none", !isExternal);

    this.internalTarget
      .querySelectorAll("select")
      .forEach((el) => (el.required = !isExternal));
    this.externalTarget.querySelectorAll("input").forEach((el) => {
      if (el.name.includes("phone")) return;
      el.required = isExternal;
    });
  }
}
