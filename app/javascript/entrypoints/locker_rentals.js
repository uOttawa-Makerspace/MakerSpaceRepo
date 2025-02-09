import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

document.addEventListener("turbo:load", () => {
  // Pass a specific element ID, else the fixed search breaks
  window.table = new DataTable("#rental-data-table", {
    language: {
      emptyTable: "Nothing.",
    },
    search: {
      fixed: {
        rentals: (a, b, c) => {
          return false;
        },
      },
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
});
