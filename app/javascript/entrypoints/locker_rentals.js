import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

document.addEventListener("turbo:load", function () {
  let table = new DataTable("#rental-data-table", {});
});
