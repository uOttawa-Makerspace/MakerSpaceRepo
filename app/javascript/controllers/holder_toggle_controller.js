import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["internal", "external"];

  connect() {
    const isExternal =
      this.element.querySelector('input[name="assignment_type"]:checked')
        ?.value === "external";
    this.applyToggle(isExternal);
  }

  toggle(event) {
    this.applyToggle(event.target.value === "external");
  }

  applyToggle(isExternal) {
    this.internalTarget.classList.toggle("d-none", isExternal);
    this.externalTarget.classList.toggle("d-none", !isExternal);

    this.internalTarget.querySelectorAll("select, input").forEach((el) => {
      el.disabled = isExternal;
      el.required = !isExternal;
    });

    this.externalTarget.querySelectorAll("input").forEach((el) => {
      el.disabled = !isExternal;
      if (el.name.includes("phone")) {
        el.required = false;
      } else {
        el.required = isExternal;
      }
    });
  }
}
