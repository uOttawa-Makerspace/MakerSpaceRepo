// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const { built, exemptPageFromCache } = vi.hoisted(() => ({
  built: [],
  exemptPageFromCache: vi.fn(),
}));
vi.mock("@hotwired/turbo-rails", () => ({
  Turbo: { cache: { exemptPageFromCache } },
}));
vi.mock("datatables.net-bs5", () => ({
  default: Object.assign(
    function DataTable(el, options) {
      el.built = true;
      built.push({ el, options });
    },
    { isDataTable: (el) => Boolean(el.built) },
  ),
}));

const { pageTable } = await import("../../app/javascript/src/page_table.js");

beforeEach(() => {
  built.length = 0;
  exemptPageFromCache.mockClear();
  document.documentElement.removeAttribute("data-widget-texts");
  document.body.innerHTML = '<table id="t"></table>';
});

const table = () => document.getElementById("t");

describe("pageTable", () => {
  it("builds the table with the given options and keeps no Turbo copy of the page", () => {
    pageTable(table(), { pageLength: 25 });
    expect(built).toEqual([{ el: table(), options: { pageLength: 25 } }]);
    expect(exemptPageFromCache).toHaveBeenCalledTimes(1);
  });

  it("words the table in the page's language", () => {
    document.documentElement.dataset.widgetTexts = JSON.stringify({
      datatables: { search: "Rechercher :" },
    });
    pageTable(table());
    expect(built[0].options).toEqual({ language: { search: "Rechercher :" } });
  });

  it("leaves a table already built as it is", () => {
    pageTable(table());
    expect(pageTable(table())).toBeNull();
    expect(built).toHaveLength(1);
  });

  it("builds nothing and keeps the Turbo copy of a page without the table", () => {
    expect(pageTable(null)).toBeNull();
    expect(built).toEqual([]);
    expect(exemptPageFromCache).not.toHaveBeenCalled();
  });
});
