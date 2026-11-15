import { Controller } from "@hotwired/stimulus";

// Stimulus defines the target accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  rowTargets: HTMLInputElement[],
}} */ (/** @type {unknown} */ (Controller));

// A select-all box that ticks or clears every row box of its table.
export default class extends TypedController {
  static targets = ["row"];

  /** @param {Event & { currentTarget: HTMLInputElement }} event */
  toggle(event) {
    this.rowTargets.forEach(
      (box) => (box.checked = event.currentTarget.checked),
    );
  }
}
