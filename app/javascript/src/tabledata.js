import { Turbo } from "@hotwired/turbo-rails";
import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import { dataTableOptions } from "./page_locale.js";

// Disable the alert in case of errors
DataTable.ext.errMode = "throw";

// DataTables moves each table into markup of its own and keeps in it only the
// rows of the page of results shown. A copy of the page, as Turbo keeps for
// going back to it, holds neither the table as it was served nor all its rows,
// so no table can be built again from that copy. Turbo keeps no copy of a page
// with such a table: going back to it loads it again, like a first visit.
document.addEventListener("turbo:load", function () {
  const tables = document.body.querySelectorAll("[data-datatable]");
  if (tables.length > 0) Turbo.cache.exemptPageFromCache();
  tables.forEach(function (el) {
    new DataTable(el, dataTableOptions(el));
  });
});
