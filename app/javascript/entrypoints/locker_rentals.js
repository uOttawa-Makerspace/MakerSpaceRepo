import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  new TomSelect("#locker_rental_preferred_locker_id");
});

document.addEventListener("turbo:load", () => {
  setupRentalTable();

  // For user facing locker request form
  let requestedAsSelect = document.getElementById("locker_rental_requested_as");
  let repoSelect = document.getElementById("repo-select");
  if (requestedAsSelect && repoSelect) {
    requestedAsSelect.addEventListener("change", function (evt) {
      if (evt.target.value === "student") {
        repoSelect.hidden = false;
        repoSelect.removeAttribute("disabled");
      } else {
        repoSelect.hidden = true;
        repoSelect.setAttribute("disabled", "");
      }
    });
    requestedAsSelect.dispatchEvent(new Event("change"));
  }
});

// Setup admin table filtering
function setupRentalTable() {
  if (!document.getElementById("rental-data-table")) {
    return;
  }

  // Pass a specific element ID, else the fixed search breaks
  let table = new DataTable("#rental-data-table", {
    language: {
      emptyTable: "Nothing.",
    },
  });

  table
    .column(0)
    .search.fixed(
      "rentalType",
      function (searchString, dataObj, rowIndex, colIndex) {
        const all_type_inputs = document.querySelectorAll(
          "#filter-locker-types input",
        );
        // For each possible checkbox
        for (let elem of all_type_inputs) {
          // Checkbox found
          if (searchString.includes(elem.dataset.type)) {
            // return checkbox value
            return elem.checked;
          }
        }
        // default to always show
        return true;
      },
    );

  table
    .column(2)
    .search.fixed(
      "rentalState",
      function (searchString, dataObj, rowIndex, colIndex) {
        const all_state_inputs = document.querySelectorAll(
          "#filter-locker-states input",
        );
        console.log(dataObj);
        for (let elem of all_state_inputs) {
          if (searchString.includes(elem.dataset.type)) {
            return elem.checked;
          }
        }
        return true;
      },
    );

  // https://datatables.net/reference/api/search.fixed()
  document
    .querySelectorAll("#filter-locker-types input, #filter-locker-states input")
    .forEach((elem) => {
      elem.addEventListener("change", (evt) => {
        table.draw();
      });
    });
}
