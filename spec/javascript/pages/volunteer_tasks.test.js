// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      this.value = el.dataset.initial ?? (config.maxItems === null ? [] : "");
      this.handlers = {};
      el.tomselect = this;
      selects.push(this);
    }
    getValue() {
      return this.value;
    }
    on(name, fn) {
      this.handlers[name] = fn;
    }
    set(value) {
      this.value = value;
      this.handlers.change?.();
    }
  },
}));

await import("../../../app/javascript/entrypoints/volunteer_tasks.js");

const $ = (id) => document.getElementById(id);
const load = (html) => {
  document.body.innerHTML = html;
  selects.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
};
const byId = (id) => selects.find((s) => s.el.id === id);

describe("task form", () => {
  it("decorates each task form select with its own options", () => {
    load(
      [
        "user_id",
        "task_certifications",
        "volunteer_id",
        "staff_id",
        "remove_staff_id",
        "remove_volunteer_id",
      ]
        .map((id) => `<select id="${id}"></select>`)
        .join(""),
    );
    expect(selects.map((s) => s.el.id)).toEqual([
      "user_id",
      "task_certifications",
      "volunteer_id",
      "staff_id",
      "remove_staff_id",
      "remove_volunteer_id",
    ]);
    expect(byId("user_id").config.maxItems).toBe(1);
    expect(byId("task_certifications").config.maxItems).toBeNull();
    expect(byId("remove_staff_id").config.closeAfterSelect).toBe(true);
  });

  it("does not decorate a select twice", () => {
    load('<select id="user_id"></select>');
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(1);
  });

  it("collects the ids of removed images and drops them from the page", () => {
    load(`<input id="deleteimages" value="">
      <div><a class="image-remove" id="11"></a></div>
      <div id="two"><a class="image-remove" id="12"></a></div>`);
    const event = new Event("click", { cancelable: true, bubbles: true });
    document.getElementById("11").dispatchEvent(event);
    document.getElementById("12").click();
    expect($("deleteimages").value).toBe("11,12,");
    expect(event.defaultPrevented).toBe(true);
    expect(document.querySelectorAll(".image-remove")).toHaveLength(0);
  });

  it("removes an image on a form without the hidden list", () => {
    load('<div><a class="image-remove" id="11"></a></div>');
    document.getElementById("11").click();
    expect(document.querySelectorAll(".image-remove")).toHaveLength(0);
  });

  it("hides and shows the completed tasks", () => {
    load(`<button id="task-hider">Hide Completed Task</button>
      <table><tr completed="completed" id="done"></tr><tr id="open"></tr></table>`);
    $("task-hider").click();
    expect($("done").classList.contains("d-none")).toBe(true);
    expect($("open").classList.contains("d-none")).toBe(false);
    expect($("task-hider").innerHTML).toBe("Show Completed Task");
    $("task-hider").click();
    expect($("done").classList.contains("d-none")).toBe(false);
    expect($("task-hider").innerHTML).toBe("Hide Completed Task");
  });
});

describe("task index filters", () => {
  const card = (id, attrs) =>
    `<div class="task-item-card-col" id="${id}" ${attrs}></div>`;
  const page = `
    <div id="volunteerTasksIndex">
      <select id="spaceFilter"></select><select id="categoryFilter"></select>
      <select id="certFilter" multiple></select>
      <input id="taskSearchInput">
      ${card("welding", 'data-searchable-text="Weld a frame" data-space="Garage" data-category="Build" data-certifications="Welding, Safety"')}
      ${card("paint", 'data-searchable-text="Paint the wall" data-space="Studio" data-category="Care" data-certifications="Safety"')}
      ${card("bare", "")}
    </div>`;

  const visible = () =>
    [...document.querySelectorAll(".task-item-card-col")]
      .filter((c) => c.style.display !== "none")
      .map((c) => c.id);

  beforeEach(() => load(page));

  it("filters by the search text, ignoring case", () => {
    $("taskSearchInput").value = "  WELD ";
    $("taskSearchInput").dispatchEvent(new Event("input"));
    expect(visible()).toEqual(["welding"]);
  });

  it("filters by space and by category", () => {
    byId("spaceFilter").set("Studio");
    expect(visible()).toEqual(["paint"]);
    byId("spaceFilter").set("");
    byId("categoryFilter").set("Build");
    expect(visible()).toEqual(["welding"]);
  });

  it("filters by any selected certification", () => {
    byId("certFilter").set(["Welding"]);
    expect(visible()).toEqual(["welding"]);
    byId("certFilter").set(["Welding", "Safety"]);
    expect(visible()).toEqual(["welding", "paint"]);
    byId("certFilter").set([]);
    expect(visible()).toEqual(["welding", "paint", "bare"]);
  });

  it("combines the filters", () => {
    byId("spaceFilter").set("Garage");
    $("taskSearchInput").value = "paint";
    $("taskSearchInput").dispatchEvent(new Event("input"));
    expect(visible()).toEqual([]);
  });

  it("reuses selects already decorated by an earlier visit", () => {
    const space = byId("spaceFilter");
    selects.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(0);
    space.set("Studio");
    expect(visible()).toEqual(["paint"]);
  });

  it("works without any of the filter controls", () => {
    load('<div id="volunteerTasksIndex"></div>');
    expect(selects).toHaveLength(0);
  });
});
