import { oncePerElement } from "./on_page.js";

// Adds a copy of the add button's input row after the rows, with an empty
// input and, in place of the add button, a button that removes the row. The
// remove button has no id, so the add button stays the only element with its
// id, and it is labelled with the add button's data-remove-label when it has
// one.
export function addInputRow(addButton) {
  const row = addButton.parentElement;
  const copy = /** @type {HTMLElement} */ (row.cloneNode(true));
  /** @type {HTMLInputElement} */ (copy.children[0]).value = null;
  const remove = copy.children[1];
  remove.removeAttribute("id");
  const label = addButton.dataset.removeLabel;
  if (label) remove.setAttribute("aria-label", label);
  remove.className = "btn btn-danger";
  remove.children[0].className = "fa fa-trash";
  row.parentElement.appendChild(copy);
  return remove;
}

// The add button of a file or photo input: each click adds another input row
// with a button that removes it.
const bindAddInputRow = oncePerElement((addButton) =>
  addButton.addEventListener("click", () => addInputRow(addButton)),
);

// The remove buttons of the added input rows, listened to on the rows' parent,
// so the rows of a page Turbo restores from its cache can be removed too.
const bindRemoveInputRow = oncePerElement((rows) =>
  rows.addEventListener("click", (event) => {
    const remove = event.target.closest(".input-group > .btn-danger");
    if (remove && rows.contains(remove)) remove.parentElement.remove();
  }),
);

// Binds the add button of a file or photo input and the remove buttons of the
// rows it adds. A missing add button is skipped.
export function bindInputRows(addButton) {
  bindAddInputRow(addButton);
  bindRemoveInputRow(addButton?.parentElement.parentElement);
}
