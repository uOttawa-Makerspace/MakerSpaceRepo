// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const instances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      el.tomselect = this;
      instances.push(this);
    }
  },
}));

await import("../../../app/javascript/entrypoints/printers.js");

const $ = (id) => document.getElementById(id);

const page = `
  <select id="model_id">
    <option value="1">Ultimaker 2+ (UM2P)</option>
    <option value="2">Replicator 2 (RPL2)</option>
  </select>
  <span id="newPrinterCode">PrinterCode</span>
  <select id="remove_printer"><option value="">Select a printer...</option></select>`;

// The page script runs on every Turbo page load.
function load(html) {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("turbo:load"));
}

beforeEach(() => {
  instances.length = 0;
});

describe("printers page script", () => {
  it("shows the code of the model picked first", () => {
    load(page);
    expect($("newPrinterCode").innerText).toBe("UM2P");
  });

  it("shows the code of the model picked next", () => {
    load(page);
    $("model_id").value = "2";
    $("model_id").dispatchEvent(new Event("change"));
    expect($("newPrinterCode").innerText).toBe("RPL2");
  });

  it("listens to the model select once over the same page", () => {
    load(page);
    const changes = vi.fn();
    $("model_id").addEventListener("change", changes);
    document.dispatchEvent(new Event("turbo:load"));
    expect(changes).not.toHaveBeenCalled();
  });

  it("makes one picker for the printer to remove, also on a later load", () => {
    load(page);
    document.dispatchEvent(new Event("turbo:load"));
    expect(instances.map((i) => i.el.id)).toEqual(["remove_printer"]);
  });

  it("shows no code when there are no printer models", () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() =>
      load(
        '<select id="model_id"></select><span id="newPrinterCode">PrinterCode</span>',
      ),
    ).not.toThrow();
    expect($("newPrinterCode").innerText).toBe("");
    expect(errors).not.toHaveBeenCalled();
    errors.mockRestore();
  });

  it("shows no code for a model without a short form", () => {
    load(page);
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    $("model_id").insertAdjacentHTML(
      "beforeend",
      '<option value="3">Prusa</option>',
    );
    $("model_id").value = "3";
    expect(() =>
      $("model_id").dispatchEvent(new Event("change")),
    ).not.toThrow();
    expect($("newPrinterCode").innerText).toBe("");
    expect(errors).not.toHaveBeenCalled();
    errors.mockRestore();
  });

  it("does nothing on a page without its fields", () => {
    expect(() => load("<p>elsewhere</p>")).not.toThrow();
    expect(instances).toEqual([]);
  });
});
