import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

// Disable the alert in case of errors
DataTable.ext.errMode = "throw";

document.addEventListener("turbo:load", function () {
  document.body.querySelectorAll("[data-datatable]").forEach(function (el) {
    new DataTable(el, {
      order: [], // this makes it so Last Seen is in descending order.
    });
  });
});
