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

await import("../../../app/javascript/entrypoints/questions.js");

const $ = (id) => document.getElementById(id);
const load = () => document.dispatchEvent(new Event("turbo:load"));

// The trainings picker of the question new and edit forms.
describe("trainings picker", () => {
  beforeEach(() => {
    document.body.innerHTML =
      '<select id="questions_trainings" multiple><option value="1">Laser</option></select>';
    selects.length = 0;
  });

  it("builds one picker with a clear button", () => {
    load();
    expect(selects).toHaveLength(1);
    expect(selects[0].el).toBe($("questions_trainings"));
    expect(selects[0].config.plugins).toEqual(["clear_button"]);
  });

  it("keeps the picker of an earlier load of the same page", () => {
    load();
    load();
    expect(selects).toHaveLength(1);
  });

  it("builds nothing on a page without the select", () => {
    document.body.innerHTML = "<p>nothing here</p>";
    load();
    expect(selects).toHaveLength(0);
  });
});
