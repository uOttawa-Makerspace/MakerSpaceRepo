// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const tomSelects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      this.enabled = true;
      el.tomselect = this;
      tomSelects.push(this);
    }
    enable() {
      this.enabled = true;
    }
    disable() {
      this.enabled = false;
    }
  },
}));

const tables = [];
const invalidated = [];
const selectedRows = [];
vi.mock("datatables.net-bs5", () => {
  class DataTable {
    static isDataTable(el) {
      return tables.some((t) => t.el === el);
    }
    static render = { select: () => "select-renderer" };
    constructor(el, options) {
      this.el = el;
      if (options) tables.push({ el, options });
    }
    cell(td) {
      return { invalidate: () => invalidated.push(td) };
    }
    rows() {
      return { nodes: () => ({ each: (fn) => selectedRows.forEach(fn) }) };
    }
  }
  return { default: DataTable };
});
vi.mock("datatables.net-select-bs5", () => ({}));

const tooltips = [];
const disposed = [];
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
  Tooltip: class {
    static getInstance(el) {
      return el.tooltipInstance;
    }
    constructor(el) {
      this.el = el;
      el.tooltipInstance = { dispose: () => disposed.push(el) };
      tooltips.push(el);
    }
  },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

await import("../../../app/javascript/entrypoints/lockers.js");

const $ = (selector) => document.querySelector(selector);
const load = () => document.dispatchEvent(new Event("turbo:load"));
const change = (el) => el.dispatchEvent(new Event("change"));
const flush = () => new Promise((r) => setTimeout(r, 0));

const calls = [];
function stubFetch(ok = true) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url, init) => {
      calls.push({ url, init });
      return { ok, text: async () => "" };
    }),
  );
}

beforeEach(() => {
  document.body.innerHTML = "";
  tomSelects.length = 0;
  tables.length = 0;
  invalidated.length = 0;
  selectedRows.length = 0;
  tooltips.length = 0;
  disposed.length = 0;
  calls.length = 0;
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("new range modal", () => {
  it("recomputes the lists while either end of the range is typed", () => {
    document.body.innerHTML = `
      <div id="newRangeLockerModal">
        <input id="newLockerRangeStart" value="1"><input id="newLockerRangeEnd" value="3">
        <div id="newRangeLockersPossible" hidden><ul></ul></div>
      </div>`;
    load();
    $("#newLockerRangeStart").dispatchEvent(new Event("input"));
    expect($("#newRangeLockersPossible").hidden).toBe(false);
    expect($("#newRangeLockersPossible li").textContent).toBe(
      "Range from 1 to 3",
    );

    $("#newLockerRangeEnd").value = "1";
    $("#newLockerRangeEnd").dispatchEvent(new Event("input"));
    expect($("#newRangeLockersPossible li").textContent).toBe("1");
  });
});

describe("locker variant selects", () => {
  const page = `
    <select class="locker-variant-select" id="a"></select>
    <select class="locker-variant-select" id="b" disabled></select>
    <input id="shopifyProductLink"><input id="value">`;

  it("decorates each select and keeps a disabled one disabled", () => {
    document.body.innerHTML = page;
    load();
    expect(tomSelects).toHaveLength(2);
    expect(tomSelects[0].enabled).toBe(true);
    expect(tomSelects[1].enabled).toBe(false);
  });

  it("does not decorate a select twice", () => {
    document.body.innerHTML = page;
    load();
    load();
    expect(tomSelects).toHaveLength(2);
  });

  it("replaces the copied picker of a select on a page restored from the cache, and keeps it disabled", () => {
    document.body.innerHTML = `
      <select class="locker-variant-select tomselected ts-hidden-accessible" id="a" tabindex="-1" disabled></select><div class="ts-wrapper"></div><div id="next"></div>`;
    load();
    expect(document.querySelectorAll(".ts-wrapper")).toHaveLength(0);
    expect($("#a").className).toBe("locker-variant-select");
    expect($("#a").nextElementSibling.id).toBe("next");
    expect(tomSelects).toHaveLength(1);
    expect(tomSelects[0].enabled).toBe(false);
  });

  it("renders an option with the product details, escaped", () => {
    document.body.innerHTML = page;
    load();
    const escape = (s) => String(s).replace(/</g, "&lt;");
    const html = tomSelects[0].config.render.option(
      {
        text: "Small",
        data: JSON.stringify({
          displayName: "Locker <S>",
          sku: "L-1",
          price: "10.00",
        }),
      },
      escape,
    );
    expect(html).toContain("Small");
    expect(html).toContain("Locker &lt;S>");
    expect(html).toContain("L-1");
    expect(html).toContain("10.00");
    expect(
      tomSelects[0].config.render.option({ text: "Bare" }, escape),
    ).toContain("Bare");
  });

  it("fills the product id from a pasted link", () => {
    document.body.innerHTML = page;
    load();
    $("#shopifyProductLink").value = "https://x.test/products/42";
    $("#shopifyProductLink").dispatchEvent(new Event("input"));
    expect($("#value").value).toBe("42");
  });
});

describe("inline size editing", () => {
  const page = `
    <input type="checkbox" id="lockerEditToggle" checked>
    <table><tr><td>
      <select data-locker-size-for="5" name="locker[size]"><option value="big" selected>Big</option></select>
      <i class="fa-check" hidden></i><span class="spinner-border" hidden></span>
    </td></tr></table>`;

  it("sends the new size, then flashes the check mark", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    document.body.innerHTML = page;
    stubFetch();
    load();
    change($("select"));

    expect($(".spinner-border").hidden).toBe(false);
    await vi.advanceTimersByTimeAsync(0);
    expect(calls[0].url).toBe("/lockers/5");
    expect(calls[0].init.method).toBe("PATCH");
    expect(calls[0].init.headers["X-CSRF-Token"]).toBe("tok");
    expect(calls[0].init.body.get("locker[size]")).toBe("big");
    expect($(".fa-check").hidden).toBe(false);
    expect($(".spinner-border").hidden).toBe(true);
    await vi.advanceTimersByTimeAsync(1500);
    expect($(".fa-check").hidden).toBe(true);
  });

  it("marks the select invalid for a while when the save fails", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    document.body.innerHTML = page;
    stubFetch(false);
    load();
    change($("select"));
    await vi.advanceTimersByTimeAsync(0);
    expect($("select").classList.contains("is-invalid")).toBe(true);
    expect($(".spinner-border").hidden).toBe(true);
    await vi.advanceTimersByTimeAsync(3000);
    expect($("select").classList.contains("is-invalid")).toBe(false);
  });

  it("disables the decorated select while saving and re-enables it when editing is on", async () => {
    document.body.innerHTML = page;
    stubFetch();
    load();
    const ts = new (await import("tom-select")).default($("select"), {});
    ts.enabled = true;
    change($("select"));
    expect(ts.enabled).toBe(false);
    await flush();
    expect(ts.enabled).toBe(true);
  });

  it("works for a select outside a table cell", async () => {
    document.body.innerHTML = `<select data-locker-size-for="6" name="s"><option value="x" selected>x</option></select>`;
    stubFetch();
    load();
    change($("select"));
    await flush();
    expect(calls[0].url).toBe("/lockers/6");
  });
});

describe("inline note editing", () => {
  const page = `
    <table id="locker_inventory_table"><tr><td data-search="old">
      <span data-bs-toggle="tooltip" title="old"><input class="locker-inline-edit" data-locker-id="8" name="locker[notes]" value="fresh"></span>
    </td></tr></table>
    <input class="locker-inline-edit" id="rental" data-rental-id="3" name="rental[notes]" value="">`;

  it("saves a locker note, refreshes the search text and the tooltip", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    document.body.innerHTML = page;
    stubFetch();
    load(); // builds the data table
    const input = $("input[data-locker-id]");
    change(input);
    await vi.advanceTimersByTimeAsync(0);

    expect(calls[0].url).toBe("/lockers/8");
    expect(calls[0].init.body.get("locker[notes]")).toBe("fresh");
    expect(input.classList.contains("is-valid")).toBe(true);
    expect($("td").getAttribute("data-search")).toBe("fresh");
    expect(invalidated).toEqual([$("td")]);
    expect($("[data-bs-toggle]").getAttribute("title")).toBe("fresh");
    expect(tooltips).toHaveLength(1);

    change(input);
    await vi.advanceTimersByTimeAsync(0);
    expect(disposed).toHaveLength(1);

    await vi.advanceTimersByTimeAsync(1500);
    expect(input.classList.contains("is-valid")).toBe(false);
  });

  it("says 'No note' on the tooltip of a cleared note", async () => {
    document.body.innerHTML = page;
    stubFetch();
    load();
    const input = $("input[data-locker-id]");
    input.value = "";
    change(input);
    await flush();
    expect($("[data-bs-toggle]").getAttribute("title")).toBe("No note");
  });

  it("sends a rental's staff note to the rental", async () => {
    document.body.innerHTML = page;
    stubFetch();
    load();
    change($("#rental"));
    await flush();
    expect(calls[0].url).toBe("/locker_rentals/3");
    expect($("#rental").closest("td")).toBeNull();
  });

  it("marks the field invalid when the save fails", async () => {
    document.body.innerHTML = page;
    stubFetch(false);
    load();
    const input = $("input[data-locker-id]");
    change(input);
    await flush();
    expect(input.classList.contains("is-invalid")).toBe(true);
    expect(input.classList.contains("is-valid")).toBe(false);
  });
});

describe("edit switch", () => {
  const page = (checked) => `
    <input type="checkbox" id="lockerEditToggle" ${checked ? "checked" : ""}>
    <select data-locker-size-for="1" id="plain"></select>
    <select data-locker-size-for="2" id="fancy"></select>
    <input class="locker-inline-edit" id="note">`;

  it("starts with the fields locked unless the switch is on", () => {
    document.body.innerHTML = page(false);
    load();
    expect($("#plain").disabled).toBe(true);
    expect($("#note").disabled).toBe(true);
  });

  it("unlocks and locks every field with the switch", async () => {
    document.body.innerHTML = page(true);
    const TomSelect = (await import("tom-select")).default;
    const fancy = new TomSelect($("#fancy"), {});
    load();
    expect($("#plain").disabled).toBe(false);
    expect(fancy.enabled).toBe(true);

    $("#lockerEditToggle").checked = false;
    change($("#lockerEditToggle"));
    expect($("#plain").disabled).toBe(true);
    expect($("#note").disabled).toBe(true);
    expect(fancy.enabled).toBe(false);

    $("#lockerEditToggle").checked = true;
    change($("#lockerEditToggle"));
    expect($("#plain").disabled).toBe(false);
    expect($("#note").disabled).toBe(false);
    expect(fancy.enabled).toBe(true);
  });

  it("applies the starting state to a decorated select too", async () => {
    document.body.innerHTML = page(false);
    const TomSelect = (await import("tom-select")).default;
    const fancy = new TomSelect($("#fancy"), {});
    load();
    expect(fancy.enabled).toBe(false);
  });
});

describe("inventory table", () => {
  const page = `
    <table id="locker_inventory_table"></table>
    <ul id="lockerBulkEditList"><li>old</li></ul>
    <div id="lockerBulkEditModal"></div>`;

  it("builds the data table once", () => {
    document.body.innerHTML = page;
    load();
    load();
    expect(tables).toHaveLength(1);
    const { options } = tables[0];
    expect(options.order).toEqual([[1, "asc"]]);
    expect(options.select.style).toBe("os");
    expect(options.columnDefs[0].render).toBe("select-renderer");
    expect($("#lockerBulkEditList").children).toHaveLength(0);
  });

  it("lists the selected lockers in the bulk edit dialog", () => {
    document.body.innerHTML = page;
    load();
    const row = (id, name) => ({
      dataset: { lockerId: id },
      cells: [{}, { innerText: name }],
    });
    selectedRows.push(row("4", "Locker 4"), row("5", "Locker 5"));
    $("#lockerBulkEditModal").dispatchEvent(new Event("show.bs.modal"));

    expect(
      [...document.querySelectorAll("#lockerBulkEditList li")].map(
        (li) => li.textContent,
      ),
    ).toEqual(["Locker 4", "Locker 5"]);
    expect(
      [...document.querySelectorAll("#lockerBulkEditList input")].map(
        (i) => `${i.name}=${i.value}`,
      ),
    ).toEqual(["id[]=4", "id[]=5"]);

    selectedRows.length = 0;
    $("#lockerBulkEditModal").dispatchEvent(new Event("show.bs.modal"));
    expect($("#lockerBulkEditList").children).toHaveLength(0);
  });

  it("does nothing on a page without the table", () => {
    document.body.innerHTML = "<p>x</p>";
    load();
    expect(tables).toHaveLength(0);
  });
});
