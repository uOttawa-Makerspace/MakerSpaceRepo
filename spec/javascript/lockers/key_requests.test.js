// @vitest-environment happy-dom
import { describe, expect, it, vi } from "vitest";

const instances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(selector, options) {
      this.selector = selector;
      this.options = options;
      selector.tomselect = this;
      instances.push(this);
    }
  },
}));
vi.mock("flatpickr", () => ({ default: {} }));

// Each load imports the page script afresh, and removes the turbo:load
// listener of the one before, so a later page load runs only the newest.
let pageLoad;
async function load(file, html) {
  document.body.innerHTML = html;
  instances.length = 0;
  vi.resetModules();
  if (pageLoad) document.removeEventListener("turbo:load", pageLoad);
  const listen = vi.spyOn(document, "addEventListener");
  await import(`../../../app/javascript/entrypoints/${file}.js`);
  pageLoad = listen.mock.calls.find(([type]) => type === "turbo:load")[1];
  listen.mockRestore();
}

describe("key_requests entry", () => {
  const html = `
    <select id="supervisor-select"></select>
    <select id="space-select"></select>`;

  it("builds tom-select widgets for supervisor and space", async () => {
    await load("key_requests", html);
    expect(instances.map((i) => i.selector.id)).toEqual([
      "supervisor-select",
      "space-select",
    ]);
    expect(instances[0].options.searchField).toEqual(["name"]);
  });

  it("skips a select that already has a widget", async () => {
    await load("key_requests", "");
    document.body.innerHTML = html;
    document.getElementById("space-select").tomselect = {};
    document.dispatchEvent(new Event("turbo:load"));
    expect(instances.map((i) => i.selector.id)).toEqual(["supervisor-select"]);
  });

  it("builds the pickers of a page restored from the cache on its load", async () => {
    await load("key_requests", html);
    document.body.innerHTML = html;
    document.dispatchEvent(new Event("turbo:load"));
    expect(instances.map((i) => i.selector.id)).toEqual([
      "supervisor-select",
      "space-select",
      "supervisor-select",
      "space-select",
    ]);
  });
});
