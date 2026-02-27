import TomSelect from "tom-select";
import DataTable from "datatables.net-bs5";
import "datatables.net-select-bs5";

// Handle grabbing the product gid on link paste
function handleLinkInput(evt) {
  const url = this.value;
  // https://admin.shopify.com/store/uottawa-makerspace/products/10478024917048?link_source=search
  const match = url.match(/\/products\/(\d+)/i);
  const id = match ? match[1] : null;

  document.querySelector("#value").value = id;
}

// Goes through a Set of numbers and returns the start and end of any continuous
// ranges in it
// findContiguous(new Set([1, 2, 3, 7, 8, 10, 11, 12]));
// => [[1, 3], [7, 8], [10, 12]]
const findContiguous = (set) => {
  // Convert string to integer
  const sorted = [...set].map(Number).sort((a, b) => a - b);
  const groups = [];
  let start = sorted[0],
    prev = sorted[0];

  for (const n of sorted.slice(1)) {
    if (n !== prev + 1) (groups.push([start, prev]), (start = n));
    prev = n;
  }
  groups.push([start, prev]);
  return groups;
};

function validateRange() {
  const rangeStart = parseInt(
    newRangeLockerModal.querySelector("#newLockerRangeStart").value,
  );
  const rangeEnd = parseInt(
    newRangeLockerModal.querySelector("#newLockerRangeEnd").value,
  );

  if (rangeStart > rangeEnd) {
    // Inverted range
  }

  if (rangeStart == rangeEnd) {
    // This is going to make one locker only.
  }

  // Find all lockers present already
  const currentLockers = new Set(
    [...document.querySelectorAll("[data-locker-specifier]")].map(
      (el) => el.dataset.lockerSpecifier,
    ),
  );
  // console.log("current lockers", currentLockers);

  // console.log("start", rangeStart, "end", rangeEnd);
  // Create a set from start to end The range input is numerical, but the
  // specifiers could be strings. This works because we're allowing numeric
  // inputs for range for now...
  const createSet = new Set(
    Array.from({ length: rangeEnd - rangeStart + 1 }, (_, i) =>
      (rangeStart + i).toString(),
    ),
  );

  // console.log("create set:", createSet);

  // Find what is not going to be created
  // This might not actually work on safari just yet
  // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set/intersection#browser_compatibility
  const lockersAlreadyThere = [...currentLockers.intersection(createSet)].sort(
    (a, b) => a.length - b.length || a.localeCompare(b),
  );
  const newRangeLockersAlreadyPresent = document.querySelector(
    "#newRangeLockersAlreadyPresent",
  );
  newRangeLockersAlreadyPresent.hidden = lockersAlreadyThere.length == 0;
  if (lockersAlreadyThere.length > 0) {
    const ul = newRangeLockersAlreadyPresent.querySelector("ul");
    ul.replaceChildren(); // Clear
    const ranges = findContiguous(lockersAlreadyThere);
    // Display ranges
    for (const range of ranges) {
      const li = document.createElement("li");
      if (range[0] == range[1]) {
        // Single locker
        li.textContent = range[0];
      } else {
        // Range of specifiers
        li.textContent = `Range from ${range[0]} to ${range[1]}`;
      }
      ul.appendChild(li);
    }
  }

  // Remove already created lockers from total range
  const lockersPossible = [...createSet.difference(currentLockers)].sort(
    (a, b) => a.length - b.length || a.localeCompare(b),
  );
  // console.log("lockers possible", lockersPossible);
  const newRangeLockersPossible = document.querySelector(
    "#newRangeLockersPossible",
  );
  newRangeLockersPossible.hidden = lockersPossible.length == 0;
  if (lockersPossible.length > 0) {
    const ul = newRangeLockersPossible.querySelector("ul");
    ul.replaceChildren(); // Clear
    const ranges = findContiguous(lockersPossible);
    // Display ranges
    for (const range of ranges) {
      const li = document.createElement("li");
      if (range[0] == range[1]) {
        // Single locker
        li.textContent = range[0];
      } else {
        // Range of specifiers
        li.textContent = `Range from ${range[0]} to ${range[1]}`;
      }
      ul.appendChild(li);
    }
  }
}

// Show a list of what's going to happen server-side when creating a range of lockers
document.addEventListener("turbo:load", function () {
  // Find modal
  const newRangeLockerModal = document.querySelector("#newRangeLockerModal");

  newRangeLockerModal
    .querySelector("#newLockerRangeStart")
    .addEventListener("input", validateRange);
  newRangeLockerModal
    .querySelector("#newLockerRangeEnd")
    .addEventListener("input", validateRange);
});

// Display a summary of available locker sizes and the associated product variant
document.addEventListener("turbo:load", function () {
  document.querySelectorAll("select.locker-variant-select").forEach((el) => {
    new TomSelect(el, {
      render: {
        option: function (data, escape) {
          let itemtitle = escape(data.text);
          let jsondata = JSON.parse(data.data);
          let title = escape(jsondata.displayName);
          let sku = escape(jsondata.sku);
          let price = escape(jsondata.price);
          return `<div>
                  <span>${itemtitle}</span> <br />
                  <span><b>Display Name:</b> ${title}</span> <br />
                  <span><b>SKU:</b> <code>${sku}</code></span> <br />
                  <span><b>Price:</b> <code>${price}</code></span>
                </div>`;
        },
      },
    });
  });

  let lockerProductLinkInput = document.querySelector("#shopifyProductLink");
  if (lockerProductLinkInput) {
    lockerProductLinkInput.addEventListener("input", handleLinkInput);
  }
});

// Inline table editing
document.addEventListener("turbo:load", function () {
  // Get all select dropdowns
  let lockerSizeSelects = document.querySelectorAll("[data-locker-size-for]");

  lockerSizeSelects.forEach((select) => {
    select.addEventListener("change", function () {
      // On select dropdown change, disable the dropdown while we send the
      // request. re-enable after we're done.
      this.tomselect.disable();

      // Find parent cell
      let cell = this.closest("td");

      // Show spinner
      let spinner = cell.querySelector(".spinner-border");
      spinner.hidden = false;

      let checkmark = cell.querySelector("i");

      let lockerId = this.dataset.lockerSizeFor;
      // console.log(`Changing ${lockerId} to ${this.value}`);

      const formData = new FormData();
      formData.append(this.name, this.value);

      const prevValue = this.tomselect.getValue();
      fetch(`/lockers/${lockerId}`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: formData,
      })
        .catch((error) => {
          console.error(error);
          // Put the value to what it was
          this.tomSelect.setValue(prevValue);
        })
        .finally(() => {
          // Hide spinner
          spinner.hidden = true;
          this.tomselect.enable();
          // Show checkmark
          checkmark.hidden = false;
          // Hide after 300ms
          setTimeout(() => {
            checkmark.hidden = true;
          }, 400);
        });
    });
  });

  const lockerAvailableSwitches = document.querySelectorAll(
    "input[name='locker[available]']",
  );

  lockerAvailableSwitches.forEach((el) => {
    el.addEventListener("change", function () {
      // Find parent cell
      let cell = this.closest("td");

      // Show spinner
      let spinner = cell.querySelector(".spinner-border");
      spinner.hidden = false;

      let checkmark = cell.querySelector("i");
      let lockerId = this.dataset.lockerId;
      const formData = new FormData();
      formData.append(this.name, this.checked);
      // console.log(lockerId)
      fetch(`/lockers/${lockerId}`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: formData,
      })
        .catch((error) => {
          console.error(error);
        })
        .finally(() => {
          // Hide spinner
          spinner.hidden = true;
          // Show checkmark
          checkmark.hidden = false;
          // Hide after 300ms
          setTimeout(() => {
            checkmark.hidden = true;
          }, 400);
        });
    });
  });

  // Toggle to prevent accidental changes
  let lockerEditToggle = document.querySelector("#lockerEditToggle");
  lockerEditToggle?.addEventListener("change", function () {
    lockerSizeSelects.forEach((el) => {
      this.checked ? el.tomselect.enable() : el.tomselect.disable();
    });
    lockerAvailableSwitches?.forEach((el) => (el.disabled = !this.checked));
  });
});

// Create the table with select plugin
document.addEventListener("turbo:load", function () {
  // Setup table selection
  let locker_inventory_table = document.querySelector(
    "#locker_inventory_table",
  );
  locker_inventory_table &&
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

  let lockerBulkEditList = document.querySelector("#lockerBulkEditList");

  // Clear list
  lockerBulkEditList?.replaceChildren();

  // Fetch list of selected rows before modal submit
  let lockerBulkEditModal = document.querySelector("#lockerBulkEditModal");
  lockerBulkEditModal &&
    locker_inventory_table &&
    lockerBulkEditModal.addEventListener("show.bs.modal", (evt) => {
      // Get all selected lockers
      new DataTable(locker_inventory_table)
        .rows({ selected: true })
        .nodes()
        .each((el) => {
          // console.log(el);
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
});
