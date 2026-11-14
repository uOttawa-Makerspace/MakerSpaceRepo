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
      built.push({ el, options });
    },
    { ext: {} },
  ),
}));
vi.mock("datatables.net-bs5/css/dataTables.bootstrap5.min.css", () => ({}));

await import("../../../app/javascript/src/tabledata.js");

function load(html) {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("turbo:load"));
}

beforeEach(() => {
  built.length = 0;
  exemptPageFromCache.mockClear();
});

describe("tabledata", () => {
  it("builds a table for each marked table on the page", () => {
    load('<table id="a" data-datatable></table><table id="b"></table>');
    expect(built.map(({ el }) => el.id)).toEqual(["a"]);
  });

  it("keeps no Turbo copy of a page with such a table", () => {
    load("<table data-datatable></table>");
    expect(exemptPageFromCache).toHaveBeenCalledTimes(1);
  });

  it("leaves the Turbo copy of a page without one alone", () => {
    load("<table></table>");
    expect(exemptPageFromCache).not.toHaveBeenCalled();
    expect(built).toEqual([]);
  });
});
