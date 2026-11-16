import { AccessorController } from "../src/accessor_controller.js";

// One row of the modal: a checked box for the booking and the date as its label, in plain text.
/** @param {[string | number, string]} date */
function dateRow([id, label]) {
  const row = document.createElement("div");
  row.className = "form-check p-2 border rounded";
  const box = document.createElement("input");
  box.className = "form-check-input";
  box.type = "checkbox";
  box.name = "sub_space_booking_ids[]";
  box.value = String(id);
  box.id = `rc_${id}`;
  box.defaultChecked = true;
  const text = document.createElement("label");
  text.className = "form-check-label w-100";
  text.htmlFor = box.id;
  text.textContent = label;
  row.append(box, text);
  return row;
}

// The modal that approves chosen dates of a recurring series: when it opens it
// lists the dates of the series whose button opened it (that button's
// data-dates), each with a checked box, and its buttons tick or clear them all.
export default class extends AccessorController {
  static targets = ["dates"];

  /** @param {Event & { relatedTarget: HTMLElement }} event */
  fill(event) {
    const dates = JSON.parse(event.relatedTarget.dataset.dates);
    this.datesTarget.replaceChildren(...dates.map(dateRow));
  }

  /** @param {{ params: { checked: boolean } }} event */
  tick({ params: { checked } }) {
    const boxes = /** @type {NodeListOf<HTMLInputElement>} */ (
      this.element.querySelectorAll('input[type="checkbox"]')
    );
    boxes.forEach((box) => (box.checked = checked));
  }
}
