// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      el.tomselect = this;
      selects.push(this);
    }
  },
}));

await import("../../../app/javascript/entrypoints/assign_staff_to_job.js");

const load = () => document.dispatchEvent(new Event("turbo:load"));
const staffSelect = (id) =>
  `<select id="jo-staff-select-${id}" class="jo-staff-select" name="staff_id"><option value="1">Staffer</option></select>`;

// The staff pickers of a job order page and of the admin job order list.
describe("staff pickers", () => {
  beforeEach(() => {
    selects.length = 0;
  });

  it("builds a picker for every row's staff select", () => {
    document.body.innerHTML = staffSelect(1) + staffSelect(2);
    load();
    expect(selects.map((s) => s.el.id)).toEqual([
      "jo-staff-select-1",
      "jo-staff-select-2",
    ]);
  });

  it("searches staff by name and shows the name, escaped", () => {
    document.body.innerHTML = staffSelect(1);
    load();
    const { config } = selects[0];
    expect(config).toMatchObject({
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: 10,
      closeAfterSelect: true,
      create: false,
    });
    const escape = (text) => text.replace("<", "&lt;");
    expect(config.render.option({ name: "<b>" }, escape)).toBe(
      "<div>&lt;b></div>",
    );
    expect(config.render.item({ name: "Ann" }, escape)).toContain(">Ann</div>");
  });

  it("keeps the pickers of an earlier load of the same page", () => {
    document.body.innerHTML = staffSelect(1) + staffSelect(2);
    load();
    load();
    expect(selects).toHaveLength(2);
  });

  it("builds nothing on a page without a staff select", () => {
    document.body.innerHTML = "<p>nothing here</p>";
    load();
    expect(selects).toHaveLength(0);
  });
});
