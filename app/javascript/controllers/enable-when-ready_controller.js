import { Controller } from "@hotwired/stimulus";

// A button rendered disabled until the page script has run, so a click cannot
// reach the server before the confirmation prompts (registered by the
// application entry) exist.
export default class extends Controller {
  connect() {
    this.element.disabled = false;
  }
}
