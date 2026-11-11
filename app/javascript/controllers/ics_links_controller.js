import { Controller } from "@hotwired/stimulus";

// Stimulus defines the target accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  listTarget: HTMLElement,
  templateTarget: HTMLElement,
}} */ (/** @type {unknown} */ (Controller));

// The list of imported calendar links: adds a blank link row from the template
// and removes a row on its delete button.
export default class extends TypedController {
  static targets = ["list", "template"];

  add() {
    const row = /** @type {HTMLElement} */ (
      this.templateTarget.cloneNode(true)
    );
    this.listTarget.append(row);
    row.removeAttribute("id");
    row.removeAttribute("data-ics-links-target");
    row.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
    row.style.visibility = "visible";
  }

  remove(event) {
    event.currentTarget.parentElement.remove();
  }
}
