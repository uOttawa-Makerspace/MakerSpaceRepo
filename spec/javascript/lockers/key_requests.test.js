// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const instances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(selector, options) {
      this.selector = selector;
      this.options = options;
      instances.push(this);
    }
  },
}));
vi.mock("flatpickr", () => ({ default: {} }));

async function load(file, html) {
  document.body.innerHTML = html;
  instances.length = 0;
  vi.resetModules();
  await import(`../../../app/javascript/entrypoints/${file}.js`);
}

describe("key_requests entry", () => {
  const html = `
    <select id="supervisor-select"></select>
    <select id="space-select"></select>
    <input id="delete_files" value="">
    <table><tr><td><span class="file-remove" id="11">a</span></td></tr>
    <tr><td><span class="file-remove" id="12">b</span></td></tr></table>`;

  it("builds tom-select widgets for supervisor and space", async () => {
    await load("key_requests", html);
    expect(instances.map((i) => i.selector)).toEqual([
      "#supervisor-select",
      "#space-select",
    ]);
    expect(instances[0].options.searchField).toEqual(["name"]);
  });

  it("skips a select that already has a widget", async () => {
    document.body.innerHTML = html;
    document.getElementById("space-select").tomselect = {};
    instances.length = 0;
    vi.resetModules();
    await import("../../../app/javascript/entrypoints/key_requests.js");
    expect(instances.map((i) => i.selector)).toEqual(["#supervisor-select"]);
  });

  it("appends the id to the delete list and removes the row on click", async () => {
    await load("key_requests", html);
    const first = document.getElementById("11");
    first.dispatchEvent(
      new Event("click", { cancelable: true, bubbles: true }),
    );
    document
      .getElementById("12")
      .dispatchEvent(new Event("click", { cancelable: true, bubbles: true }));
    expect(document.getElementById("delete_files").value).toBe("11,12,");
    expect(document.querySelectorAll("tr")).toHaveLength(0);
  });
});
