// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const sortables = [];
vi.mock("sortablejs", () => ({
  default: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      this.sort = options.sort;
      this.option = vi.fn((name, value) => (this[name] = value));
      sortables.push(this);
    }
  },
}));
const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.config = config;
      selects.push(this);
    }
  },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));
const toasts = vi.hoisted(() => []);
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

const $ = (id) => document.getElementById(id);

// Each load imports the page script afresh, so the document listeners the
// previous import added are removed first; otherwise every earlier example's
// turbo:load handler would run again and the result would depend on the order.
const documentListeners = [];

async function load(html) {
  for (const [type, handler] of documentListeners.splice(0)) {
    document.removeEventListener(type, handler);
  }
  document.body.innerHTML = html;
  sortables.length = 0;
  selects.length = 0;
  vi.resetModules();
  const listen = vi.spyOn(document, "addEventListener");
  await import("../../../app/javascript/entrypoints/learning_modules.js");
  documentListeners.push(...listen.mock.calls.map(([type, fn]) => [type, fn]));
  listen.mockRestore();
}

beforeEach(() => {
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("reordering", () => {
  const page = `
    <input type="checkbox" data-order="a" id="switch">
    <div data-order-container="a" id="list">
      <div data-id="3"><span class="sort-handle" hidden></span></div>
      <div data-id="4"><span class="sort-handle" hidden></span></div>
    </div>`;

  it("makes the list sortable only while the switch is on", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    expect(sortables).toHaveLength(1);
    expect(sortables[0].options.sort).toBe(false);
    expect(sortables[0].options.handle).toBe(".sort-handle");

    $("switch").checked = true;
    $("switch").dispatchEvent(new Event("change"));
    expect(sortables[0].option).toHaveBeenCalledWith("sort", true);
    expect(
      [...document.querySelectorAll(".sort-handle")].map((h) => h.hidden),
    ).toEqual([false, false]);

    $("switch").checked = false;
    $("switch").dispatchEvent(new Event("change"));
    expect(
      [...document.querySelectorAll(".sort-handle")].map((h) => h.hidden),
    ).toEqual([true, true]);
  });

  it("saves the new order when a drag ends", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    const fetchMock = vi.fn(async () => ({}));
    vi.stubGlobal("fetch", fetchMock);
    $("list").append($("list").firstElementChild);
    sortables[0].options.onEnd({ from: $("list") });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/learning_area/reorder");
    expect(init.method).toBe("PUT");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(JSON.parse(init.body)).toEqual({ data: ["4", "3"], format: "json" });
  });

  it("tells the user when the order could not be sent", async () => {
    await load(page);
    document.documentElement.dataset.requestNetwork = "Server unreachable";
    toasts.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    sortables[0].options.onEnd({ from: $("list") });
    await vi.waitFor(() =>
      expect(toasts).toEqual([
        { message: "Server unreachable", type: "error" },
      ]),
    );
  });

  it("lets a subskill be chosen or typed", async () => {
    await load('<select id="learning_module_subskill"></select>');
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects[0].config.create).toBe(true);
    expect(selects[0].config.maxItems).toBe(1);
  });
});
