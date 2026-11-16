import { Turbo } from "@hotwired/turbo-rails";
import DataTable from "datatables.net-bs5";
import { dataTableOptions } from "./page_locale.js";

// The DataTable of a page script's own table, with its texts in the page's
// language. A copy of the page, as Turbo keeps for going back to it, holds
// neither the table as it was served nor all its rows (see tabledata.js), so
// Turbo keeps no copy of the page: going back to it loads it again, like a
// first visit. A table already built is left as it is, and a page without the
// table builds nothing.
export function pageTable(table, options = {}) {
  if (!table || DataTable.isDataTable(table)) return null;
  Turbo.cache.exemptPageFromCache();
  return new DataTable(table, dataTableOptions(table, options));
}
