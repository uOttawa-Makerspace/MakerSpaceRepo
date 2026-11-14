// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      this.cleared = 0;
      this.optionsCleared = 0;
      this.synced = 0;
      this.destroyed = 0;
      el.tomselect = this;
      selects.push(this);
    }
    clear() {
      this.cleared++;
    }
    clearOptions() {
      this.optionsCleared++;
    }
    sync() {
      this.synced++;
    }
    destroy() {
      this.destroyed++;
      delete this.el.tomselect;
    }
  },
}));

await import("../../../app/javascript/src/settings.js");

const $ = (id) => document.getElementById(id);
const load = (html) => {
  document.body.innerHTML = html;
  selects.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
};
const chooseFaculty = (value) => {
  $("user_faculty").value = value;
  $("user_faculty").dispatchEvent(new Event("change"));
};

// The program select of the sign-up and profile forms, narrowed to the
// programs of the chosen faculty.
describe("faculty and program", () => {
  const page = `
    <select id="user_faculty"><option value="Eng">Eng</option><option value="Sci">Sci</option></select>
    <select id="user_program">
      <optgroup label="Eng"><option>Civil</option></optgroup>
      <optgroup label="Sci"><option>Physics</option></optgroup>
    </select>`;

  beforeEach(() => load(page));

  it("decorates the program select with its options", () => {
    expect(selects).toHaveLength(1);
    expect(selects[0].el).toBe($("user_program"));
    expect(selects[0].config).toEqual({
      maxItems: 1,
      maxOptions: null,
      searchOnKeyUp: true,
    });
  });

  it("offers only the programs of the chosen faculty", () => {
    chooseFaculty("Sci");
    const groups = [...$("user_program").querySelectorAll("optgroup")];
    expect(groups.map((g) => g.label)).toEqual(["Sci"]);
    expect(selects[0]).toMatchObject({
      cleared: 1,
      optionsCleared: 1,
      synced: 1,
    });
  });

  it("can offer a faculty's programs again after another faculty", () => {
    chooseFaculty("Sci");
    chooseFaculty("Eng");
    const groups = [...$("user_program").querySelectorAll("optgroup")];
    expect(groups.map((g) => g.label)).toEqual(["Eng"]);
  });

  it("offers no programs for a faculty without any", () => {
    $("user_faculty").insertAdjacentHTML(
      "beforeend",
      '<option value="Art">Art</option>',
    );
    chooseFaculty("Art");
    expect($("user_program").querySelectorAll("optgroup")).toHaveLength(0);
  });

  it("replaces the picker of an earlier load of the same page", () => {
    const first = selects[0];
    selects.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(first.destroyed).toBe(1);
    expect(selects).toHaveLength(1);
  });

  it("removes the picker before Turbo caches the page", () => {
    document.dispatchEvent(new Event("turbo:before-cache"));
    expect(selects[0].destroyed).toBe(1);
    expect($("user_program").tomselect).toBeUndefined();
  });

  it("narrows the options without a picker left to refresh", () => {
    $("user_program").tomselect.destroy();
    chooseFaculty("Sci");
    const groups = [...$("user_program").querySelectorAll("optgroup")];
    expect(groups.map((g) => g.label)).toEqual(["Sci"]);
    expect(selects[0].cleared).toBe(0);
  });
});

describe("pages without the program select", () => {
  it("builds nothing", () => {
    load("<p>nothing here</p>");
    expect(selects).toHaveLength(0);
    expect(() =>
      document.dispatchEvent(new Event("turbo:before-cache")),
    ).not.toThrow();
  });

  it("works without a faculty select", () => {
    load('<select id="user_program"></select>');
    expect(selects).toHaveLength(1);
  });
});
