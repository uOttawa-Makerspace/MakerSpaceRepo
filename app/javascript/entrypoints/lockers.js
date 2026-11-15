import { Tooltip } from "bootstrap";
import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { pageTable } from "../src/page_table.js";
import { newTomSelect } from "../src/tom_select.js";
import DataTable from "datatables.net-bs5";
import "datatables.net-select-bs5";
import { csrfHeaders } from "../src/csrf";
import { reportFailure, requestJson } from "../src/request_error";

// Handle grabbing the product gid on link paste
export function handleLinkInput() {
  const url = this.value;
  const match = url.match(/\/products\/(\d+)/i);
  const id = match ? match[1] : null;

  const valueInput = document.querySelector("#value");
  if (valueInput && id) {
    valueInput.value = id;
  }
}

// Goes through a Set of numbers and returns the start and end of any continuous ranges in it
export const findContiguous = (set) => {
  const sorted = [...set].map(Number).sort((a, b) => a - b);
  if (sorted.length === 0) return [];
  const groups = [];
  let start = sorted[0],
    prev = sorted[0];

  for (const n of sorted.slice(1)) {
    if (n !== prev + 1) {
      groups.push([start, prev]);
      start = n;
    }
    prev = n;
  }
  groups.push([start, prev]);
  return groups;
};

export function validateRange() {
  const modal = document.querySelector("#newRangeLockerModal");
  if (!modal) return;

  const createSet = requestedRange(modal);
  if (!createSet) return;

  const existing = existingSpecifiers(modal);
  showLockerRanges(modal.querySelector("#newRangeLockersAlreadyPresent"), [
    ...existing.intersection(createSet),
  ]);
  showLockerRanges(modal.querySelector("#newRangeLockersPossible"), [
    ...createSet.difference(existing),
  ]);
}

// A whole number as the server's Integer(text, 10) reads one: spaces around it,
// an optional sign, an optional 0d prefix and digits, which single underscores
// may group. Anything else, such as "1abc" or "1.5", is NaN.
const WHOLE_NUMBER = /^\s*([+-]?)(?:0d)?(\d+(?:_\d+)*)\s*$/i;

function wholeNumber(text) {
  const match = WHOLE_NUMBER.exec(text);
  return match ? Number(match[1] + match[2].replaceAll("_", "")) : NaN;
}

// The specifiers from the start field to the end field, or null while either
// is not a whole number or the start is above the end.
function requestedRange(modal) {
  const startInput = modal.querySelector("#newLockerRangeStart");
  const endInput = modal.querySelector("#newLockerRangeEnd");
  if (!startInput || !endInput) return null;

  const rangeStart = wholeNumber(startInput.value);
  const rangeEnd = wholeNumber(endInput.value);

  if (isNaN(rangeStart) || isNaN(rangeEnd) || rangeStart > rangeEnd)
    return null;

  return new Set(
    Array.from({ length: rangeEnd - rangeStart + 1 }, (_, i) =>
      (rangeStart + i).toString(),
    ),
  );
}

// The specifiers of every existing locker, which the page renders on the
// modal. They are compared as text, as the server does: a range makes the
// lockers "1", "2", ..., so a locker named "01" or "A1" is not one of them.
function existingSpecifiers(modal) {
  return new Set(JSON.parse(modal.dataset.lockerSpecifiers || "[]"));
}

// Lists the specifiers as collapsed ranges in the list, or empties and hides
// the list when there are none.
function showLockerRanges(list, specifiers) {
  if (!list) return;

  list
    .querySelector("ul")
    .replaceChildren(...findContiguous(specifiers).map(rangeItem));
  list.hidden = specifiers.length === 0;
}

function rangeItem([first, last]) {
  const li = document.createElement("li");
  li.textContent = first === last ? first : `Range from ${first} to ${last}`;
  return li;
}

// Show a list of what's going to happen server-side when creating a range of lockers
const bindRangeInput = oncePerElement((input) =>
  input.addEventListener("input", validateRange),
);

onEveryPageLoad(() => {
  const newRangeLockerModal = document.querySelector("#newRangeLockerModal");
  if (!newRangeLockerModal) return;
  bindRangeInput(newRangeLockerModal.querySelector("#newLockerRangeStart"));
  bindRangeInput(newRangeLockerModal.querySelector("#newLockerRangeEnd"));
});

// Display a summary of available locker sizes and the associated product variant
function renderVariantOption(data, escape) {
  let itemtitle = escape(data.text);
  let jsondata = (data.data && JSON.parse(data.data)) || {};
  let title = escape(jsondata.displayName || "");
  let sku = escape(jsondata.sku || "");
  let price = escape(jsondata.price || "");
  return `<div>
                    <span>${itemtitle}</span> <br />
                    <span><b>Display Name:</b> ${title}</span> <br />
                    <span><b>SKU:</b> <code>${sku}</code></span> <br />
                    <span><b>Price:</b> <code>${price}</code></span>
                  </div>`;
}

const bindLinkInput = oncePerElement((input) =>
  input.addEventListener("input", handleLinkInput),
);

onEveryPageLoad(() => {
  document.querySelectorAll("select.locker-variant-select").forEach((el) => {
    if (!el.tomselect) {
      newTomSelect(el, { render: { option: renderVariantOption } });
      // Match initial disabled state
      if (el.disabled && el.tomselect) {
        el.tomselect.disable();
      }
    }
  });

  bindLinkInput(document.querySelector("#shopifyProductLink"));
});

// Inline table editing (Size, Type, and Notes)
const inlineEditToggle = () => document.querySelector("#lockerEditToggle");

// 1. AJAX handler for locker size/variant dropdown
function saveLockerSize() {
  if (this.tomselect) this.tomselect.disable();

  const cell = this.closest("td");
  const spinner = cell?.querySelector(".spinner-border");
  const checkmark = cell?.querySelector(".fa-check, i");
  if (spinner) spinner.hidden = false;

  const lockerId = this.dataset.lockerSizeFor;
  const formData = new FormData();
  formData.append(this.name, this.value);

  requestJson(`/lockers/${lockerId}`, {
    method: "PATCH",
    headers: csrfHeaders({ Accept: "application/json" }),
    body: formData,
  })
    .then(() => {
      if (checkmark) {
        checkmark.hidden = false;
        setTimeout(() => {
          checkmark.hidden = true;
        }, 1500);
      }
    })
    .catch((error) => {
      reportFailure(error);
      this.classList.add("is-invalid");
      setTimeout(() => this.classList.remove("is-invalid"), 3000);
    })
    .finally(() => {
      if (spinner) spinner.hidden = true;
      if (this.tomselect && inlineEditToggle()?.checked) {
        this.tomselect.enable();
      }
    });
}

// 2. AJAX handler for Type (Audience) dropdown and Notes text field (handles both lockers and locker_rentals)
function saveInlineEdit() {
  const lockerId = this.dataset.lockerId;
  const rentalId = this.dataset.rentalId;

  // Direct to locker_rentals if editing an assigned rental's staff notes, else to lockers
  const url = rentalId ? `/locker_rentals/${rentalId}` : `/lockers/${lockerId}`;

  const formData = new FormData();
  formData.append(this.name, this.value);

  requestJson(url, {
    method: "PATCH",
    headers: csrfHeaders({ Accept: "application/json" }),
    body: formData,
  })
    .then(() => {
      this.classList.add("is-valid");
      refreshSearchText(this);
      refreshTooltip(this);
      setTimeout(() => this.classList.remove("is-valid"), 1500);
    })
    .catch((error) => {
      reportFailure(error);
      this.classList.add("is-invalid");
      setTimeout(() => this.classList.remove("is-invalid"), 3000);
    });
}

// Update the cell's data-search attribute so table searching works with the new text immediately
function refreshSearchText(input) {
  const td = input.closest("td");
  if (!td) return;
  td.setAttribute("data-search", input.value);
  const table = document.querySelector("#locker_inventory_table");
  if (table && DataTable.isDataTable(table)) {
    new DataTable(table).cell(td).invalidate();
  }
}

function refreshTooltip(input) {
  const tooltipWrapper = input.closest('[data-bs-toggle="tooltip"]');
  if (!tooltipWrapper) return;
  // dispose puts the old text back as the title, so set the new text after it
  const existingTooltip = Tooltip.getInstance(tooltipWrapper);
  if (existingTooltip) existingTooltip.dispose();
  tooltipWrapper.setAttribute("title", input.value || "No note");
  new Tooltip(tooltipWrapper);
}

// 3. Toggle switch to enable/disable all inline fields at once
function setInlineEditing(enabled) {
  // Toggle Size Dropdowns (TomSelect)
  document.querySelectorAll("[data-locker-size-for]").forEach((el) => {
    if (el.tomselect) {
      enabled ? el.tomselect.enable() : el.tomselect.disable();
    } else {
      el.disabled = !enabled;
    }
  });

  // Toggle Type dropdowns and Notes text inputs
  document
    .querySelectorAll(".locker-inline-edit")
    .forEach((el) => (el.disabled = !enabled));
}

const bindSizeSelect = oncePerElement((select) =>
  select.addEventListener("change", saveLockerSize),
);
const bindInlineEdit = oncePerElement((input) =>
  input.addEventListener("change", saveInlineEdit),
);
const bindEditToggle = oncePerElement((toggle) =>
  toggle.addEventListener("change", () => setInlineEditing(toggle.checked)),
);

onEveryPageLoad(() => {
  document.querySelectorAll("[data-locker-size-for]").forEach(bindSizeSelect);
  document.querySelectorAll(".locker-inline-edit").forEach(bindInlineEdit);

  const lockerEditToggle = inlineEditToggle();
  if (lockerEditToggle) {
    // Set initial state based on toggle switch
    setInlineEditing(lockerEditToggle.checked);
    bindEditToggle(lockerEditToggle);
  }
});

// The inventory table, with a select column, built when the page is loaded
// and on every later Turbo load (see pageTable).
onEveryPageLoad(() => {
  const table = /** @type {HTMLTableElement} */ (
    document.querySelector("#locker_inventory_table")
  );
  if (!table) return;
  pageTable(table, {
    language: {
      search: "_INPUT_",
      searchPlaceholder: table.dataset.searchPlaceholder,
    },
    columnDefs: [
      {
        orderable: false,
        render: DataTable.render.select(),
        targets: 0,
      },
    ],
    select: {
      style: "os",
      selector: "td:first-child",
    },
    order: [[1, "asc"]],
  });
});

// The bulk edit dialog lists the lockers selected in the inventory table
function listSelectedLockers(table, list) {
  list.replaceChildren();
  const dt = new DataTable(table);
  dt.rows({ selected: true })
    .nodes()
    .each((el) => {
      const li = document.createElement("li");
      li.textContent = el.cells[1].innerText;
      list.appendChild(li);

      const field = document.createElement("input");
      field.type = "hidden";
      field.name = "id[]";
      field.value = el.dataset.lockerId;
      list.appendChild(field);
    });
}

const bindBulkEditModal = oncePerElement((modal) =>
  modal.addEventListener("show.bs.modal", () =>
    listSelectedLockers(
      document.querySelector("#locker_inventory_table"),
      document.querySelector("#lockerBulkEditList"),
    ),
  ),
);

onEveryPageLoad(() => {
  const locker_inventory_table = document.querySelector(
    "#locker_inventory_table",
  );
  const lockerBulkEditList = document.querySelector("#lockerBulkEditList");
  const lockerBulkEditModal = document.querySelector("#lockerBulkEditModal");

  lockerBulkEditList?.replaceChildren();

  if (lockerBulkEditModal && locker_inventory_table) {
    bindBulkEditModal(lockerBulkEditModal);
  }
});
