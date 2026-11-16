import { Controller } from "@hotwired/stimulus";

// Asks for confirmation before a button, link or form acts. The element is
// rendered disabled by the server, so a click before this controller connects
// cannot reach the server unconfirmed; connecting enables it. When the person
// declines, the click or submit is cancelled before Turbo or the browser sees it.
export default class extends Controller {
  static values = { message: String };

  connect() {
    if ("disabled" in this.element) {
      /** @type {HTMLButtonElement} */ (this.element).disabled = false;
    }
  }

  ask(event) {
    // Stimulus defines messageValue at runtime; the cast tells the type checker.
    if (window.confirm(/** @type {any} */ (this).messageValue)) {
      // Lets a script act only after an accepted prompt, whatever the order of click listeners.
      this.dispatch("confirmed");
      return;
    }
    event.preventDefault();
    // Stops other listeners on this element and Turbo's own handlers from acting on a declined click.
    event.stopImmediatePropagation();
  }
}
