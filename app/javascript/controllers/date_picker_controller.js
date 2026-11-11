import { Controller } from "@hotwired/stimulus";
import flatpickr from "flatpickr";

// A flatpickr calendar on the input target; the clear action empties it.
export default class extends Controller {
  static targets = ["input"];

  connect() {
    // Stimulus defines inputTarget at runtime; the cast tells the type checker.
    const input = /** @type {any} */ (this).inputTarget;
    this.picker = flatpickr(input, {
      enableTime: false,
      dateFormat: "Y-m-d",
      minDate: "today",
      altInput: true,
      altFormat: "F j, Y",
      allowInput: false,
    });
  }

  disconnect() {
    this.picker?.destroy();
  }

  clear() {
    this.picker.clear();
  }
}
