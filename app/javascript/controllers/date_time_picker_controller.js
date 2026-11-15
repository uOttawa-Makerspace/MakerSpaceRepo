import { Controller } from "@hotwired/stimulus";
import flatpickr from "flatpickr";
import { DATE_TIME, flatpickrOptions } from "../src/page_locale.js";

// A date and time picker on the input, in the page's language.
export default class extends Controller {
  connect() {
    this.picker = flatpickr(
      this.element,
      flatpickrOptions(this.element, DATE_TIME, "date_time"),
    );
  }

  // Leaves a plain input in the copy Turbo caches, so a restore makes one picker.
  disconnect() {
    this.picker.destroy();
  }
}
