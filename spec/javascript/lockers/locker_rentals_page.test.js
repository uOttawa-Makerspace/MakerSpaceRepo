// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(selector, config) {
      this.selector = selector;
      this.config = config;
      selects.push(this);
    }
  },
}));
vi.mock("datatables.net-bs5/css/dataTables.bootstrap5.min.css", () => ({}));

await import("../../../app/javascript/entrypoints/locker_rentals.js");

const load = () => document.dispatchEvent(new Event("turbo:load"));
const $ = (id) => document.getElementById(id);
const escape = (s) => String(s).replace(/</g, "&lt;");

beforeEach(() => {
  selects.length = 0;
  document.body.innerHTML = "";
});

describe("preferred locker picker", () => {
  beforeEach(() => {
    document.body.innerHTML =
      '<select id="locker_rental_preferred_locker_id"></select>';
    load();
  });

  it("decorates the select", () => {
    expect(selects).toHaveLength(1);
    expect(selects[0].selector).toBe("#locker_rental_preferred_locker_id");
  });

  it.each(["option", "item"])("renders %s with the number and size", (kind) => {
    const html = selects[0].config.render[kind](
      { text: "12", size: "Large" },
      escape,
    );
    expect(html).toBe("<div>Locker 12 - Size Large</div>");
  });

  it("marks a staff only locker", () => {
    const html = selects[0].config.render.option(
      { text: "3", size: "<S>", staffOnly: "true" },
      escape,
    );
    expect(html).toBe("<div>Locker 3 - Size &lt;S> - Staff only</div>");
  });

  it("does nothing on a page without the select", () => {
    selects.length = 0;
    document.body.innerHTML = "<p>x</p>";
    load();
    expect(selects).toHaveLength(0);
  });
});

describe("requested as", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <select id="locker_rental_requested_as">
        <option value="student">Student</option><option value="staff">Staff</option>
      </select>
      <div id="repo-select" disabled></div>`;
    load();
  });

  it("shows the course field for a student on load", () => {
    expect($("repo-select").hidden).toBe(false);
    expect($("repo-select").hasAttribute("disabled")).toBe(false);
  });

  it("hides and disables it for anyone else, and restores it for a student", () => {
    const select = $("locker_rental_requested_as");
    select.value = "staff";
    select.dispatchEvent(new Event("change"));
    expect($("repo-select").hidden).toBe(true);
    expect($("repo-select").hasAttribute("disabled")).toBe(true);

    select.value = "student";
    select.dispatchEvent(new Event("change"));
    expect($("repo-select").hidden).toBe(false);
    expect($("repo-select").hasAttribute("disabled")).toBe(false);
  });

  it("is left alone when only one of the two fields is on the page", () => {
    document.body.innerHTML =
      '<select id="locker_rental_requested_as"></select>';
    expect(load).not.toThrow();
  });
});
