import { Controller } from "@hotwired/stimulus";
import TomSelect from "tom-select";

// Tell TomSelect to use Bootstrap's classes
const bootstrapClasses = {
  input_class: "form-select",
  invalid_cls: "is-invalid",
};

const lockerLine = (data, escape) => {
  const size = escape(data.size || "");
  const text = escape(data.text || "");
  const staffOnly = data.staffOnly === "true" ? " - Staff only" : "";
  return `<div>Locker ${text} - Size ${size}${staffOnly}</div>`;
};

const userLine = (data, escape) => {
  const role = data.role
    ? `<span class="badge text-bg-primary ms-2">${escape(data.role)}</span>`
    : "";
  return `<div>${escape(data.text)}${role}</div>`;
};

// Turns the locker select and the user select inside its own form into
// searchable pickers. Each form carries its own copy of the controller, so the
// selects need no shared id.
export default class extends Controller {
  static targets = ["locker", "user"];

  lockerTargetConnected(select) {
    if (select.tomselect) return;
    new TomSelect(select, {
      create: false,
      maxItems: 1,
      ...bootstrapClasses,
      render: { option: lockerLine, item: lockerLine },
    });
  }

  userTargetConnected(select) {
    if (select.tomselect) return;
    // Search by name or username
    new TomSelect(select, {
      maxItems: 1,
      valueField: "value",
      labelField: "text",
      searchField: ["text"],
      ...bootstrapClasses,
      render: { option: userLine, item: userLine },
    });
  }

  lockerTargetDisconnected(select) {
    select.tomselect?.destroy();
  }

  userTargetDisconnected(select) {
    select.tomselect?.destroy();
  }
}
