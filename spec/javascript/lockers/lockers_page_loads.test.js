// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      el.tomselect = this;
      selects.push(this);
    }
    enable() {}
    disable() {}
  },
}));
vi.mock("datatables.net-bs5", () => ({ default: class {} }));
vi.mock("datatables.net-select-bs5", () => ({}));
vi.mock("bootstrap", () => ({ Tooltip: class {} }));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: () => ({}),
}));

const $ = (id) => document.getElementById(id);

// Each example imports the page script afresh over its page, without a
// turbo:load, as Turbo does when it adds the script on a visit after that
// visit's turbo:load. The listeners of the import are removed afterwards.
const documentListeners = [];
async function importOver(html) {
  document.body.innerHTML = html;
  selects.length = 0;
  vi.resetModules();
  const listen = vi.spyOn(document, "addEventListener");
  await import("../../../app/javascript/entrypoints/lockers.js");
  documentListeners.push(...listen.mock.calls.map(([type, fn]) => [type, fn]));
  listen.mockRestore();
}
const turboLoad = () => document.dispatchEvent(new Event("turbo:load"));

afterEach(() => {
  for (const [type, fn] of documentListeners.splice(0)) {
    document.removeEventListener(type, fn);
  }
  vi.unstubAllGlobals();
});

const inventory = `
  <input type="checkbox" id="lockerEditToggle">
  <table><tr><td>
    <select class="locker-variant-select" data-locker-size-for="5" name="locker[locker_size_id]" disabled></select>
  </td><td>
    <input class="locker-inline-edit" id="note" name="locker[notes]" data-locker-id="5" disabled>
  </td></tr></table>
  <input id="shopifyProductLink"><input id="value">
  <div id="newRangeLockerModal" data-locker-specifiers="[]">
    <input id="newLockerRangeStart" value="1"><input id="newLockerRangeEnd" value="2">
    <div id="newRangeLockersPossible" hidden><ul></ul></div>
  </div>`;

describe("lockers page script reached by a Turbo visit", () => {
  it("sets up the page it came with before any turbo:load", async () => {
    await importOver(inventory);

    expect(selects.map((s) => s.el)).toEqual([
      document.querySelector("select"),
    ]);

    $("lockerEditToggle").checked = true;
    $("lockerEditToggle").dispatchEvent(new Event("change"));
    expect($("note").disabled).toBe(false);

    $("shopifyProductLink").value = "https://x.test/products/42";
    $("shopifyProductLink").dispatchEvent(new Event("input"));
    expect($("value").value).toBe("42");

    $("newLockerRangeStart").dispatchEvent(new Event("input"));
    expect($("newRangeLockersPossible").hidden).toBe(false);
  });

  it("binds each control once over a later load of the same page", async () => {
    await importOver(inventory);
    turboLoad();
    expect(selects).toHaveLength(1);

    const fetch = vi.fn(() => new Promise(() => {}));
    vi.stubGlobal("fetch", fetch);
    $("note").dispatchEvent(new Event("change"));
    document.querySelector("select").dispatchEvent(new Event("change"));
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("sets up the inventory of a later page", async () => {
    await importOver("<p>another page</p>");
    document.body.innerHTML = inventory;
    turboLoad();
    expect(selects).toHaveLength(1);
    $("lockerEditToggle").checked = true;
    $("lockerEditToggle").dispatchEvent(new Event("change"));
    expect($("note").disabled).toBe(false);
  });
});
