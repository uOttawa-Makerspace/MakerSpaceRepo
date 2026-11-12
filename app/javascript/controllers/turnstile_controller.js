import { Controller } from "@hotwired/stimulus";
import { afterPageLoad, loadScript } from "../src/load_script.js";

const API =
  "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

// Loads Cloudflare Turnstile after the page has loaded and renders the check
// into its own element. If the script cannot be loaded, a message explains why
// the form cannot be sent; the server still refuses a submission with no token.
export default class extends Controller {
  static values = { unavailableMessage: String };

  connect() {
    this.cancel = afterPageLoad(() => this.load());
  }

  disconnect() {
    this.cancel?.();
    this.notice?.remove();
    if (this.widgetId !== undefined) {
      /** @type {any} */ (window).turnstile?.remove(this.widgetId);
      this.widgetId = undefined;
    }
  }

  load() {
    // A page restored from Turbo's cache already holds the rendered check; start from an empty element.
    this.element.replaceChildren();
    loadScript(API)
      .then(() => this.render())
      .catch(() => this.showUnavailable());
  }

  render() {
    if (!this.element.isConnected) return;
    this.widgetId = /** @type {any} */ (window).turnstile.render(this.element, {
      sitekey: /** @type {HTMLElement} */ (this.element).dataset.sitekey,
    });
  }

  showUnavailable() {
    if (!this.element.isConnected) return;
    this.notice = document.createElement("p");
    this.notice.setAttribute("role", "alert");
    this.notice.className = "text-danger small mb-0";
    this.notice.textContent = /** @type {any} */ (this).unavailableMessageValue;
    this.element.append(this.notice);
  }
}
