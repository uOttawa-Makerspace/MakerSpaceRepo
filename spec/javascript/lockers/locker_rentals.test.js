// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const tables = [];
vi.mock("datatables.net-bs5", () => ({
  default: class {
    constructor(selector, options) {
      this.selector = selector;
      this.options = options;
      this.fixed = {};
      this.draws = 0;
      this.column = (n) => ({
        search: { fixed: (name, fn) => (this.fixed[`${n}:${name}`] = fn) },
      });
      this.draw = () => this.draws++;
      tables.push(this);
    }
  },
}));
vi.mock("datatables.net-bs5/css/dataTables.bootstrap5.min.css", () => ({}));
vi.mock("tom-select", () => ({ default: class {} }));

const { setupRentalTable } =
  await import("../../../app/javascript/entrypoints/locker_rentals.js");

describe("setupRentalTable", () => {
  beforeEach(() => {
    tables.length = 0;
    vi.spyOn(console, "log").mockImplementation(() => {});
    document.body.innerHTML = "";
  });

  it("does nothing when the page has no rental table", () => {
    setupRentalTable();
    expect(tables).toHaveLength(0);
  });

  describe("with a table and filter checkboxes", () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <table id="rental-data-table"></table>
        <div id="filter-locker-types">
          <input type="checkbox" data-type="general" checked>
          <input type="checkbox" data-type="staff">
        </div>
        <div id="filter-locker-states">
          <input type="checkbox" data-type="active" checked>
        </div>`;
      setupRentalTable();
    });

    it("creates the table with an empty-table message", () => {
      expect(tables[0].selector).toBe("#rental-data-table");
      expect(tables[0].options.language.emptyTable).toBe("Nothing.");
    });

    it("shows a row whose type box is checked and hides an unchecked one", () => {
      const type = tables[0].fixed["0:rentalType"];
      expect(type("general", {}, 0, 0)).toBe(true);
      expect(type("staff", {}, 0, 0)).toBe(false);
    });

    it("shows rows of a type with no checkbox", () => {
      expect(tables[0].fixed["0:rentalType"]("gng", {}, 0, 0)).toBe(true);
    });

    it("filters the state column by its checkboxes", () => {
      const state = tables[0].fixed["2:rentalState"];
      expect(state("active", {}, 0, 2)).toBe(true);
      document.querySelector("#filter-locker-states input").checked = false;
      expect(state("active", {}, 0, 2)).toBe(false);
      expect(state("expired", {}, 0, 2)).toBe(true);
    });

    it("redraws the table when a filter box changes", () => {
      document
        .querySelector("#filter-locker-types input")
        .dispatchEvent(new Event("change"));
      expect(tables[0].draws).toBe(1);
    });
  });
});
