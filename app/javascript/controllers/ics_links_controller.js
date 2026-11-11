import { Controller } from "@hotwired/stimulus";

// Stimulus defines the target accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  listTarget: HTMLElement,
  templateTarget: HTMLTemplateElement,
}} */ (/** @type {unknown} */ (Controller));

// The list of imported calendar links: adds a blank link row from the template
// and removes a row on its delete button.
export default class extends TypedController {
  static targets = ["list", "template"];

  add() {
    this.listTarget.append(this.templateTarget.content.cloneNode(true));
  }

  remove(event) {
    event.currentTarget.closest("[data-ics-links-row]").remove();
  }
}
