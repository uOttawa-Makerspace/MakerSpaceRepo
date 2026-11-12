import { Controller } from "@hotwired/stimulus";
import { afterPageLoad, loadScript } from "../src/load_script.js";

// Loads the UserWay accessibility widget after the page has loaded. If the
// host cannot be reached the widget is simply absent; nothing else changes.
export default class extends Controller {
  static values = { src: String, account: String };

  connect() {
    this.cancel = afterPageLoad(() => this.load());
  }

  disconnect() {
    this.cancel?.();
  }

  load() {
    const { srcValue, accountValue } = /** @type {any} */ (this);
    loadScript(srcValue, { "data-account": accountValue }).catch(() => {
      /** @type {HTMLElement} */ (this.element).dataset.state = "unavailable";
    });
  }
}
