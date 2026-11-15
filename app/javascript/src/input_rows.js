// Adds a copy of the add button's input row after the rows, with an empty
// input and, in place of the add button, a button that removes the row. The
// remove button has no id, so the add button stays the only element with its
// id, and it is labelled with the add button's data-remove-label.
export function addInputRow(addButton) {
  const row = addButton.parentElement;
  const copy = /** @type {HTMLElement} */ (row.cloneNode(true));
  /** @type {HTMLInputElement} */ (copy.children[0]).value = null;
  const remove = copy.children[1];
  remove.removeAttribute("id");
  remove.setAttribute("aria-label", addButton.dataset.removeLabel);
  remove.className = "btn btn-danger";
  remove.children[0].className = "fa fa-trash";
  row.parentElement.appendChild(copy);
  return remove;
}
