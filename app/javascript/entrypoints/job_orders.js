import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

document.addEventListener("turbo:load", () => {
  new DataTable(".table", {
    order: [[3, "desc"]],
    pageLength: 25,
  });
});
