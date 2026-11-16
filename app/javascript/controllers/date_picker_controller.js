import { Controller } from "@hotwired/stimulus";
import flatpickr from "flatpickr";
import { flatpickrOptions } from "../src/page_locale.js";

// A flatpickr calendar on the input target; the clear action empties it.
export default class extends Controller {
  static targets = ["input"];

  connect() {
    // Stimulus defines inputTarget at runtime; the cast tells the type checker.
    const input = /** @type {any} */ (this).inputTarget;
    this.picker = flatpickr(
      input,
      flatpickrOptions(
        input,
        {
          enableTime: false,
          dateFormat: "Y-m-d",
          minDate: "today",
          altInput: true,
          allowInput: false,
        },
        "date",
      ),
    );
    this.labelVisibleInput(input);
  }

  disconnect() {
    // Give the label back to the original input so a later connect finds it again.
    this.label?.setAttribute("for", this.labelTarget);
    this.label = null;
    this.picker?.destroy();
  }

  // flatpickr hides the original input and shows a copy without an id, which leaves the
  // label pointing at a hidden field. Point the label at the visible copy instead.
  labelVisibleInput(input) {
    const label = this.element.querySelector(`label[for="${input.id}"]`);
    if (!label) return;
    this.label = label;
    this.labelTarget = input.id;
    this.picker.altInput.id = `${input.id}_display`;
    label.setAttribute("for", this.picker.altInput.id);
  }

  clear() {
    this.picker.clear();
  }
}
