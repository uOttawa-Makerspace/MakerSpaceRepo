import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import { dataTableOptions } from "./page_locale.js";

// Disable the alert in case of errors
DataTable.ext.errMode = "throw";

document.addEventListener("turbo:load", function () {
  document.body.querySelectorAll("[data-datatable]").forEach(function (el) {
    new DataTable(el, dataTableOptions(el));
  });
});
