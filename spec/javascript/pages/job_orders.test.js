// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const tables = [];
const searchFilters = [];
vi.mock("datatables.net-bs5", () => {
  class DataTable {
    static ext = { search: searchFilters };
    constructor(selector, options) {
      this.selector = selector;
      this.options = options;
      this.searches = {};
      this.draws = 0;
      tables.push(this);
    }
    column(n) {
      return { search: (...args) => (this.searches[n] = args) };
    }
    draw() {
      this.draws++;
    }
  }
  return { default: DataTable };
});
vi.mock("datatables.net-bs5/css/dataTables.bootstrap5.min.css", () => ({}));

await import("../../../app/javascript/entrypoints/job_orders.js");

const $ = (id) => document.getElementById(id);
const checkbox = (name, value, checked = false) =>
  `<input type="checkbox" name="${name}[]" value="${value}" ${checked ? "checked" : ""}>`;

const PAGE = `
<select id="date_range">
  <option value="30">Last 30</option><option value="all">All</option><option value="semester">Term</option>
</select>
<label><input type="radio" name="date_range" id="default_date" value="all" checked> All time</label>
<label><input type="radio" name="date_range" id="week" value="7"> Last week</label>
<label><input type="radio" name="date_range" id="term" value="semester"> This semester</label>
<input id="computed_days" value="x">
${checkbox("job_type_filter", "Laser")}${checkbox("job_type_filter", "3D Print")}
${checkbox("job_status_filter", "Open")}${checkbox("job_status_filter", "Paid (Waiting for Payment)")}
${checkbox("assigned_to_filter", "Ann")}${checkbox("assigned_to_filter", "Assign")}
<div id="active-filters" class="d-none"></div><div id="filter-tags"></div>
<button id="clear-filters"></button>`;

function load(path = "/job_orders/admin", page = PAGE) {
  window.happyDOM.setURL(`http://localhost${path}`);
  document.body.innerHTML = page;
  tables.length = 0;
  searchFilters.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  return tables[0];
}

const box = (name, value) =>
  document.querySelector(`input[name="${name}[]"][value="${value}"]`);
const tick = (el) => {
  el.checked = true;
  el.dispatchEvent(new Event("change"));
};
const tags = () =>
  [...document.querySelectorAll("#filter-tags span")].map((s) => s.textContent);

afterEach(() => vi.useRealTimers());

describe("job order tables", () => {
  it("makes each table sortable by newest first, 25 to a page", () => {
    const dt = load("/job_orders", "<table class='table'></table>");
    expect(dt.selector).toBe(".table:not(.notDataTable)");
    expect(dt.options).toEqual({ order: [[3, "desc"]], pageLength: 25 });
  });

  it("adds no filters outside the admin page", () => {
    load("/job_orders", PAGE);
    $("clear-filters").click();
    expect(tables[0].draws).toBe(0);
  });
});

describe("admin filters", () => {
  beforeEach(() => load());

  it("searches the type and assignee columns for the ticked values", () => {
    tick(box("job_type_filter", "Laser"));
    tick(box("job_type_filter", "3D Print"));
    tick(box("assigned_to_filter", "Ann"));
    const { searches, draws } = tables[0];
    expect(searches[5]).toEqual(["Laser|3D Print", true, false]);
    expect(searches[7]).toEqual(["Ann", false, false]);
    expect(draws).toBe(3);
  });

  it("drops the waiting for payment suffix from the status search", () => {
    tick(box("job_status_filter", "Open"));
    tick(box("job_status_filter", "Paid (Waiting for Payment)"));
    expect(tables[0].searches[6]).toEqual(["Open|Paid", true, false]);
  });

  it("clears a column search when nothing is ticked", () => {
    tick(box("job_type_filter", "Laser"));
    box("job_type_filter", "Laser").checked = false;
    box("job_type_filter", "Laser").dispatchEvent(new Event("change"));
    expect(tables[0].searches[5]).toEqual(["", true, false]);
  });

  it("labels the active filters, showing Assign as Unassigned", () => {
    expect($("active-filters").classList.contains("d-none")).toBe(true);
    tick(box("job_type_filter", "Laser"));
    tick(box("assigned_to_filter", "Assign"));
    expect($("active-filters").classList.contains("d-none")).toBe(false);
    expect(tags()).toEqual(["Laser", "Unassigned"]);
  });

  it("hides the active filters when everything is cleared", () => {
    tick(box("job_type_filter", "Laser"));
    $("clear-filters").click();
    expect(box("job_type_filter", "Laser").checked).toBe(false);
    expect($("active-filters").classList.contains("d-none")).toBe(true);
    expect(tags()).toEqual([]);
  });

  it("shows the chosen date range as a tag", () => {
    $("week").checked = true;
    $("default_date").checked = false;
    tick(box("job_type_filter", "Laser"));
    expect(tags()).toEqual(["Last week", "Laser"]);
  });

  it("shows no tag for all time", () => {
    tick(box("job_type_filter", "Laser"));
    expect(tags()).not.toContain("All time");
  });
});

describe("date range", () => {
  it("is as wide as the select asks and as long as the radio's days", () => {
    load();
    $("date_range").value = "30";
    $("date_range").dispatchEvent(new Event("change"));
    expect($("computed_days").value).toBe("30");

    $("date_range").value = "all";
    $("date_range").dispatchEvent(new Event("change"));
    expect($("computed_days").value).toBe("1000000");
  });

  it("counts the days since the start of the current semester", () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(2026, 5, 10, 12));
    load();
    $("date_range").value = "semester";
    $("date_range").dispatchEvent(new Event("change"));
    expect(Number($("computed_days").value)).toBe(40); // since May 1
  });

  it("restores all time when the filters are cleared", () => {
    load();
    $("computed_days").value = "7";
    $("clear-filters").click();
    expect($("computed_days").value).toBe("1000000");
  });

  it("keeps only the rows submitted within the computed days", () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(2026, 5, 10, 12));
    load();
    $("computed_days").value = "7";
    tick(box("job_type_filter", "Laser"));
    const keep = searchFilters[0];
    // The visible text is localised; only the data-sort timestamp is read.
    const settings = (sort, text = "15 juin 2023 à 14:30") => {
      const cell = document.createElement("td");
      if (sort) cell.dataset.sort = sort;
      cell.textContent = text;
      return { aoData: [{ anCells: [0, 0, 0, 0, cell] }] };
    };
    expect(keep(settings("2026-06-08T10:00:00-04:00"), [], 0)).toBe(true);
    expect(keep(settings("2026-05-01T10:00:00-04:00"), [], 0)).toBe(false);
    expect(keep(settings(null), [], 0)).toBe(true);
    expect(keep({}, [], 0)).toBe(true);
  });

  it("registers the date filter once however often the filters change", () => {
    load();
    tick(box("job_type_filter", "Laser"));
    tick(box("job_status_filter", "Open"));
    tick(box("assigned_to_filter", "Ann"));
    expect(searchFilters).toHaveLength(1);
  });

  it("replaces the date filter when the admin page is visited again", () => {
    load();
    document.dispatchEvent(new Event("turbo:load"));
    expect(searchFilters).toHaveLength(1);
  });

  it("removes the date filter when leaving the admin page", () => {
    load();
    window.happyDOM.setURL("http://localhost/job_orders");
    document.body.innerHTML = "<table class='table'></table>";
    document.dispatchEvent(new Event("turbo:load"));
    expect(searchFilters).toHaveLength(0);
  });
});
