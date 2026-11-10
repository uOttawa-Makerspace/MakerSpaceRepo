import { Controller } from "@hotwired/stimulus";
import flatpickr from "flatpickr";

// A flatpickr calendar on the input target; the clear action empties it.
export default class extends Controller {
  static targets = ["input"];

  connect() {
    this.picker = flatpickr(this.inputTarget, {
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
