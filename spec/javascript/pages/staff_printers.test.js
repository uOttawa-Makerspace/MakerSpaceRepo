// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

const selects = [];
const attempts = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(target, config) {
      attempts.push(target);
      const el =
        typeof target === "string" ? document.querySelector(target) : target;
      if (!el) throw new Error("no element");
      this.el = el;
      this.config = config;
      this.value = "";
      el.tomselect = this;
      selects.push(this);
    }
    getValue() {
      return this.value;
    }
    addOption() {}
    refreshOptions() {}
    setValue(v) {
      this.value = v;
    }
  },
}));

const flush = () => new Promise((r) => setTimeout(r, 0));
const byEl = (id) => selects.find((s) => s.el.id === id);

async function loadStaffPrinters(html) {
  document.body.innerHTML = html;
  selects.length = 0;
  attempts.length = 0;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/staff_printers.js");
  document.dispatchEvent(new Event("turbo:load"));
  await flush();
}

const SEND_FORM =
  '<select id="printerNumberSelect"></select><select id="user_dashboard_select"></select>';

describe("staff_printers", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("builds no selects on a page without the send form", async () => {
    await loadStaffPrinters("<p>nothing here</p>");
    expect(attempts).toEqual([]);
  });

  it("fills the user from the last session of the chosen printer", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ 5: { id: 1, username: "ann", name: "Ann" } }),
    });
    vi.stubGlobal("fetch", fetchMock);
    await loadStaffPrinters(
      '<select id="user_dashboard_select"></select><select id="printerNumberSelect"></select>',
    );
    new (await import("tom-select")).default("#user_dashboard_select", {});
    byEl("printerNumberSelect").config.onChange("5");
    expect(byEl("user_dashboard_select").value).toBe("ann");
    byEl("user_dashboard_select").value = "typed";
    byEl("user_dashboard_select").setValue("typed");
    byEl("printerNumberSelect").config.onChange("5");
    expect(byEl("user_dashboard_select").value).toBe("typed");
  });

  it("reports a failed response instead of parsing it", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const json = vi.fn();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json }));
    await loadStaffPrinters(SEND_FORM);
    expect(json).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalled();
    expect(byEl("printerNumberSelect")).toBeDefined();
  });

  it("does not fetch on pages without the printer select", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    await loadStaffPrinters("<div></div>");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("reports a rejected lookup and leaves the prefill empty", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    await loadStaffPrinters(SEND_FORM);
    expect(error).toHaveBeenCalled();
    new (await import("tom-select")).default("#user_dashboard_select", {});
    byEl("printerNumberSelect").config.onChange("5");
    expect(byEl("user_dashboard_select").value).toBe("");
  });
});
