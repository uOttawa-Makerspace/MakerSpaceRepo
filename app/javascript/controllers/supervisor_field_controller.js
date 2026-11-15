import { AccessorController } from "../src/accessor_controller.js";

// The access-request form shows its supervisor list only while the Staff identity is chosen.
export default class extends AccessorController {
  static targets = ["supervisor"];

  /** @param {Event & { target: HTMLInputElement }} event */
  toggle({ target }) {
    this.supervisorTarget.style.display =
      target.value === "Staff" ? "block" : "none";
  }
}
