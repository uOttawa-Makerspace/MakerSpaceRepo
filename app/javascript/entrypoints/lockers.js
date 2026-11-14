import { Tooltip } from "bootstrap";
import TomSelect from "tom-select";
import { dataTableOptions, tomSelectOptions } from "../src/page_locale.js";
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
document.addEventListener("turbo:load", function () {
  const newRangeLockerModal = document.querySelector("#newRangeLockerModal");
  if (newRangeLockerModal) {
    newRangeLockerModal
      .querySelector("#newLockerRangeStart")
      ?.addEventListener("input", validateRange);
    newRangeLockerModal
      .querySelector("#newLockerRangeEnd")
      ?.addEventListener("input", validateRange);
  }
});

// Display a summary of available locker sizes and the associated product variant
document.addEventListener("turbo:load", function () {
  document.querySelectorAll("select.locker-variant-select").forEach((el) => {
    if (!el.tomselect) {
      new TomSelect(
        el,
        tomSelectOptions(el, {
          render: {
            option: function (data, escape) {
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
            },
          },
        }),
      );
      // Match initial disabled state
      if (el.disabled && el.tomselect) {
        el.tomselect.disable();
      }
    }
  });

  const lockerProductLinkInput = document.querySelector("#shopifyProductLink");
  if (lockerProductLinkInput) {
    lockerProductLinkInput.addEventListener("input", handleLinkInput);
  }
});

// Inline table editing (Size, Type, and Notes)
document.addEventListener("turbo:load", function () {
  const lockerSizeSelects = document.querySelectorAll("[data-locker-size-for]");
  const inlineEditInputs = document.querySelectorAll(".locker-inline-edit");
  const lockerEditToggle = document.querySelector("#lockerEditToggle");

  // 1. AJAX handler for locker size/variant dropdown
  lockerSizeSelects.forEach((select) => {
    select.addEventListener("change", function () {
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
          if (this.tomselect && lockerEditToggle?.checked) {
            this.tomselect.enable();
          }
        });
    });
  });

  // 2. AJAX handler for Type (Audience) dropdown and Notes text field (handles both lockers and locker_rentals)
  inlineEditInputs.forEach((input) => {
    input.addEventListener("change", function () {
      const lockerId = this.dataset.lockerId;
      const rentalId = this.dataset.rentalId;

      // Direct to locker_rentals if editing an assigned rental's staff notes, else to lockers
      const url = rentalId
        ? `/locker_rentals/${rentalId}`
        : `/lockers/${lockerId}`;

      const formData = new FormData();
      formData.append(this.name, this.value);

      requestJson(url, {
        method: "PATCH",
        headers: csrfHeaders({ Accept: "application/json" }),
        body: formData,
      })
        .then(() => {
          this.classList.add("is-valid");

          // 1. Update the cell's data-search attribute so table searching works with the new text immediately
          const td = this.closest("td");
          if (td) {
            td.setAttribute("data-search", this.value);
            const table = document.querySelector("#locker_inventory_table");
            if (table && DataTable.isDataTable(table)) {
              new DataTable(table).cell(td).invalidate();
            }
          }

          // 2. Update tooltip
          const tooltipWrapper = this.closest('[data-bs-toggle="tooltip"]');
          if (tooltipWrapper) {
            // dispose puts the old text back as the title, so set the new text after it
            const existingTooltip = Tooltip.getInstance(tooltipWrapper);
            if (existingTooltip) existingTooltip.dispose();
            tooltipWrapper.setAttribute("title", this.value || "No note");
            new Tooltip(tooltipWrapper);
          }

          setTimeout(() => this.classList.remove("is-valid"), 1500);
        })
        .catch((error) => {
          reportFailure(error);
          this.classList.add("is-invalid");
          setTimeout(() => this.classList.remove("is-invalid"), 3000);
        });
    });
  });

  // 3. Toggle switch to enable/disable all inline fields at once
  if (lockerEditToggle) {
    // Set initial state based on toggle switch
    lockerSizeSelects.forEach((el) => {
      if (el.tomselect) {
        lockerEditToggle.checked
          ? el.tomselect.enable()
          : el.tomselect.disable();
      } else {
        el.disabled = !lockerEditToggle.checked;
      }
    });
    inlineEditInputs.forEach((el) => (el.disabled = !lockerEditToggle.checked));

    lockerEditToggle.addEventListener("change", function () {
      // Toggle Size Dropdowns (TomSelect)
      lockerSizeSelects.forEach((el) => {
        if (el.tomselect) {
          this.checked ? el.tomselect.enable() : el.tomselect.disable();
        } else {
          el.disabled = !this.checked;
        }
      });

      // Toggle Type dropdowns and Notes text inputs
      inlineEditInputs.forEach((el) => {
        el.disabled = !this.checked;
      });
    });
  }
});

// Initialize DataTable with select plugin
document.addEventListener("turbo:load", function () {
  const locker_inventory_table = /** @type {HTMLTableElement} */ (
    document.querySelector("#locker_inventory_table")
  );
  if (
    locker_inventory_table &&
    !DataTable.isDataTable(locker_inventory_table)
  ) {
    new DataTable(
      locker_inventory_table,
      dataTableOptions(locker_inventory_table, {
        language: {
          search: "_INPUT_",
          searchPlaceholder: locker_inventory_table.dataset.searchPlaceholder,
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
      }),
    );
  }

  const lockerBulkEditList = document.querySelector("#lockerBulkEditList");
  const lockerBulkEditModal = document.querySelector("#lockerBulkEditModal");

  lockerBulkEditList?.replaceChildren();

  if (lockerBulkEditModal && locker_inventory_table) {
    lockerBulkEditModal.addEventListener("show.bs.modal", () => {
      lockerBulkEditList.replaceChildren();
      const dt = new DataTable(locker_inventory_table);
      dt.rows({ selected: true })
        .nodes()
        .each((el) => {
          const li = document.createElement("li");
          li.textContent = el.cells[1].innerText;
          lockerBulkEditList.appendChild(li);

          const field = document.createElement("input");
          field.type = "hidden";
          field.name = "id[]";
          field.value = el.dataset.lockerId;
          lockerBulkEditList.appendChild(field);
        });
    });
  }
});
