import { AccessorController } from "../src/accessor_controller.js";

// A select-all box that ticks or clears every row box of its table.
export default class extends AccessorController {
  static targets = ["row"];

  /** @param {Event & { currentTarget: HTMLInputElement }} event */
  toggle(event) {
    this.rowTargets.forEach(
      (box) => (box.checked = event.currentTarget.checked),
    );
  }
}
