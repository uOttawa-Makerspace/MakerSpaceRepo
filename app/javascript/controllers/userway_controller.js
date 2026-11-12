import { Controller } from "@hotwired/stimulus";
import { afterPageLoad, loadScript } from "../src/load_script.js";

// Loads the UserWay accessibility widget after the page has loaded. If the
// host cannot be reached the widget is simply absent; nothing else changes.
// The vendor script adds its button and menus to <body> and runs once per
// document, so Turbo's body swap would remove them. Before each render the
// controller moves those nodes into the incoming body, leaving one widget.
const WIDGET_NODES =
  ".userway_buttons_wrapper, [data-uw-rm-ignore], [data-uw-styling-context], [class*='userway'], [id*='userway']";

export default class extends Controller {
  static values = { src: String, account: String };

  connect() {
    this.cancel = afterPageLoad(() => this.load());
  }

  disconnect() {
    this.cancel?.();
  }

  keepWidget(event) {
    const incoming = event.detail.newBody;
    [...document.body.children]
      .filter((node) => node.matches(WIDGET_NODES) && node !== this.element)
      .forEach((node) => incoming.append(node));
  }

  load() {
    const { srcValue, accountValue } = /** @type {any} */ (this);
    loadScript(srcValue, { "data-account": accountValue }).catch(() => {
      /** @type {HTMLElement} */ (this.element).dataset.state = "unavailable";
    });
  }
}
