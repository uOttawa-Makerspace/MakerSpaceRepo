import TomSelect from "tom-select";
import DataTable from "datatables.net-bs5";
import "datatables.net-select-bs5";

// Checkbox to toggle the student section on the form
document.addEventListener("turbo:load", function () {
  document
    .querySelector("#locker_rental_requested_as")
    ?.addEventListener("change", function () {
      const repoSelect = document.querySelector("#repo-select");
      if (repoSelect) {
        repoSelect.hidden = !this.checked;
        repoSelect.disabled = !this.checked;
      }
    });
});

// Handle grabbing the product gid on link paste
function handleLinkInput() {
  const url = this.value;
  const match = url.match(/\/products\/(\d+)/i);
  const id = match ? match[1] : null;

  const valueInput = document.querySelector("#value");
  if (valueInput && id) {
    valueInput.value = id;
  }
}

// Goes through a Set of numbers and returns the start and end of any continuous ranges in it
const findContiguous = (set) => {
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

function validateRange() {
  const modal = document.querySelector("#newRangeLockerModal");
  if (!modal) return;

  const startInput = modal.querySelector("#newLockerRangeStart");
  const endInput = modal.querySelector("#newLockerRangeEnd");
  if (!startInput || !endInput) return;

  const rangeStart = parseInt(startInput.value);
  const rangeEnd = parseInt(endInput.value);

  if (isNaN(rangeStart) || isNaN(rangeEnd) || rangeStart > rangeEnd) return;

  // Find all lockers present already
  const currentLockers = new Set(
    [...document.querySelectorAll("[data-locker-specifier]")].map(
      (el) => el.dataset.lockerSpecifier,
    ),
  );

  const createSet = new Set(
    Array.from({ length: rangeEnd - rangeStart + 1 }, (_, i) =>
      (rangeStart + i).toString(),
    ),
  );

  const lockersAlreadyThere = [...currentLockers.intersection(createSet)].sort(
    (a, b) => a.length - b.length || a.localeCompare(b),
  );
  const newRangeLockersAlreadyPresent = document.querySelector(
    "#newRangeLockersAlreadyPresent",
  );
  if (newRangeLockersAlreadyPresent) {
    newRangeLockersAlreadyPresent.hidden = lockersAlreadyThere.length === 0;
    if (lockersAlreadyThere.length > 0) {
      const ul = newRangeLockersAlreadyPresent.querySelector("ul");
      ul.replaceChildren();
      const ranges = findContiguous(lockersAlreadyThere);
      for (const range of ranges) {
        const li = document.createElement("li");
        li.textContent =
          range[0] === range[1]
            ? range[0]
            : `Range from ${range[0]} to ${range[1]}`;
        ul.appendChild(li);
      }
    }
  }

  const lockersPossible = [...createSet.difference(currentLockers)].sort(
    (a, b) => a.length - b.length || a.localeCompare(b),
  );
  const newRangeLockersPossible = document.querySelector(
    "#newRangeLockersPossible",
  );
  if (newRangeLockersPossible) {
    newRangeLockersPossible.hidden = lockersPossible.length === 0;
    if (lockersPossible.length > 0) {
      const ul = newRangeLockersPossible.querySelector("ul");
      ul.replaceChildren();
      const ranges = findContiguous(lockersPossible);
      for (const range of ranges) {
        const li = document.createElement("li");
        li.textContent =
          range[0] === range[1]
            ? range[0]
            : `Range from ${range[0]} to ${range[1]}`;
        ul.appendChild(li);
      }
    }
  }
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
      new TomSelect(el, {
        render: {
          option: function (data, escape) {
            let itemtitle = escape(data.text);
            let jsondata = data.data ? JSON.parse(data.data) : {};
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
      });
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

      const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

      fetch(`/lockers/${lockerId}`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": csrfToken,
          Accept: "application/json",
        },
        body: formData,
      })
        .then((response) => {
          if (!response.ok) throw new Error("Failed to update size");
          if (checkmark) {
            checkmark.hidden = false;
            setTimeout(() => {
              checkmark.hidden = true;
            }, 1500);
          }
        })
        .catch((error) => {
          console.error(error);
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

  // 2. AJAX handler for Type (Audience) dropdown and Notes text field
  inlineEditInputs.forEach((input) => {
    input.addEventListener("change", function () {
      const lockerId = this.dataset.lockerId;
      const formData = new FormData();
      formData.append(this.name, this.value);

      const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

      fetch(`/lockers/${lockerId}`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": csrfToken,
          Accept: "application/json",
        },
        body: formData,
      })
        .then((response) => {
          if (!response.ok) throw new Error("Failed to update locker details");
          this.classList.add("is-valid");
          setTimeout(() => this.classList.remove("is-valid"), 1500);
        })
        .catch((error) => {
          console.error(error);
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
  const locker_inventory_table = document.querySelector(
    "#locker_inventory_table",
  );
  if (
    locker_inventory_table &&
    !DataTable.isDataTable(locker_inventory_table)
  ) {
    new DataTable(locker_inventory_table, {
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
