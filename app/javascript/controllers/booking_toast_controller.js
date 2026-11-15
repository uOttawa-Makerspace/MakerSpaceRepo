import { Toast } from "bootstrap";

import { AccessorController } from "../src/accessor_controller.js";

// The booking page's toast. Its data attributes hold the page's translated
// texts (data-failed-title="Booking failed"); it is red for a problem and green
// for a success.
export default class extends AccessorController {
  static targets = ["title", "text"];

  // The page's text of that name, or "" when it has none.
  /** @param {string} name */
  text(name) {
    return this.element.dataset[name] ?? "";
  }

  // Shows the text under the page's title of that name.
  /** @param {string} titleName @param {string} text */
  show(titleName, text, success = false) {
    const [on, off] = success ? ["success", "danger"] : ["danger", "success"];
    const header = this.element.querySelector(".toast-header");
    for (const el of [this.element, header]) {
      el?.classList.add(`text-bg-${on}`);
      el?.classList.remove(`text-bg-${off}`);
    }
    this.titleTarget.innerText = this.text(titleName);
    this.textTarget.innerText = text;
    Toast.getOrCreateInstance(this.element).show();
  }
}
