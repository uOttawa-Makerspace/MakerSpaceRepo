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
      // the real TomSelect gives its control the select's tabindex, then -1 to the select
      this.tabIndex = el.tabIndex || 0;
      el.tabIndex = -1;
      el.tomselect = this;
      selects.push(this);
    }
    getValue() {
      return this.value;
    }
    on(name, fn) {
      (this.handlers[name] ??= []).push(fn);
    }
    set(value) {
      this.value = value;
      (this.handlers.change ?? []).forEach((fn) => fn());
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

  // the edit form's image card: the remove button sits in the card footer
  const imageCard = (id) =>
    `<div class="image-item" id="card-${id}"><div class="card"><img alt=""><div class="card-footer"><a class="image-remove" id="${id}"></a></div></div></div>`;

  it("collects the ids of removed images and drops them from the page", () => {
    load(`<div id="image-container">${imageCard(11)}${imageCard(12)}
      <input id="deleteimages" value=""></div>`);
    const event = new Event("click", { cancelable: true, bubbles: true });
    document.getElementById("11").dispatchEvent(event);
    document.getElementById("12").click();
    expect($("deleteimages").value).toBe("11,12,");
    expect(event.defaultPrevented).toBe(true);
    expect(document.querySelectorAll(".image-item, img")).toHaveLength(0);
    expect($("image-container").contains($("deleteimages"))).toBe(true);
  });

  it("records a remove button outside an image card and removes nothing", () => {
    load(
      `<input id="deleteimages" value=""><div id="box"><a class="image-remove" id="11"></a></div>`,
    );
    $("11").click();
    expect($("deleteimages").value).toBe("11,");
    expect($("box")).not.toBeNull();
  });

  it("removes an image on a form without the hidden list", () => {
    load(imageCard(11));
    document.getElementById("11").click();
    expect($("card-11")).toBeNull();
  });

  it("leaves a completed task toggle alone, as no page has one", () => {
    load(`<button id="task-hider">Hide Completed Task</button>
      <table><tr completed="completed" id="done"></tr></table>`);
    $("task-hider").click();
    expect($("done").classList.contains("d-none")).toBe(false);
    expect($("task-hider").innerHTML).toBe("Hide Completed Task");
  });

  it("binds each page control once when the same page loads a second time", () => {
    load(`<input id="deleteimages" value="">${imageCard(11)}`);
    document.dispatchEvent(new Event("turbo:load"));
    $("11").click();
    expect($("deleteimages").value).toBe("11,");
  });

  it("binds the copies of the controls on a page restored from the cache", () => {
    load(`<input id="deleteimages" value="">${imageCard(11)}`);
    document.body.replaceWith(document.body.cloneNode(true));
    document.dispatchEvent(new Event("turbo:load"));
    $("11").click();
    expect($("deleteimages").value).toBe("11,");
  });

  it("replaces the copied picker of a form select on a page restored from the cache", () => {
    load(
      `<select id="user_id" class="form-select tomselected ts-hidden-accessible"></select><div class="ts-wrapper" id="copy"></div><div id="next"></div>`,
    );
    expect(selects.map((s) => s.el.id)).toEqual(["user_id"]);
    expect($("copy")).toBeNull();
    expect($("next")).not.toBeNull();
    expect($("user_id").className).toBe("form-select");
  });

  it("lets the new picker of a copied select be reached with Tab", () => {
    load(
      `<select id="user_id" class="tomselected ts-hidden-accessible" tabindex="-1" data-view-tabindex=""></select><div class="ts-wrapper"></div>`,
    );
    expect(byId("user_id").tabIndex).toBe(0);
  });

  it("lets the new picker of a copied select without a kept tabindex be reached with Tab", () => {
    load(
      `<select id="user_id" class="tomselected ts-hidden-accessible" tabindex="-1"></select><div class="ts-wrapper"></div>`,
    );
    expect(byId("user_id").tabIndex).toBe(0);
  });

  it("gives the new picker of a copied select the tabindex the view set", () => {
    load(
      `<select id="user_id" class="tomselected ts-hidden-accessible" tabindex="-1" data-view-tabindex="3"></select><div class="ts-wrapper"></div>`,
    );
    expect(byId("user_id").tabIndex).toBe(3);
  });

  it("keeps the tabindex the view set on a select it decorates", () => {
    load(`<select id="user_id" tabindex="3"></select>`);
    expect($("user_id").dataset.viewTabindex).toBe("3");
    expect(byId("user_id").tabIndex).toBe(3);
  });

  it("keeps the element after a copied select when it is not a picker", () => {
    load(
      `<select id="user_id" class="tomselected"></select><div id="next"></div>`,
    );
    expect($("next")).not.toBeNull();
    expect($("user_id").className).toBe("");
  });

  it("does nothing on a page without the task controls", () => {
    load("<p>nothing here</p>");
    expect(selects).toHaveLength(0);
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

  it("replaces the copied pickers of the filter selects on a page restored from the cache", () => {
    load(`<div id="volunteerTasksIndex">
      <select id="spaceFilter" class="tomselected ts-hidden-accessible"></select><div class="ts-wrapper"></div>
      <select id="categoryFilter" class="tomselected ts-hidden-accessible"></select><div class="ts-wrapper"></div>
      <select id="certFilter" class="tomselected ts-hidden-accessible" multiple></select><div class="ts-wrapper"></div>
    </div>`);
    expect(selects).toHaveLength(3);
    expect(document.querySelectorAll(".ts-wrapper")).toHaveLength(0);
    expect(document.querySelectorAll(".tomselected")).toHaveLength(0);
  });

  it("works without any of the filter controls", () => {
    load('<div id="volunteerTasksIndex"></div>');
    expect(selects).toHaveLength(0);
  });

  it("gives each filter select its own options", () => {
    expect(byId("spaceFilter").config).toEqual({
      allowEmptyOption: true,
      create: false,
      controlInput: null,
    });
    expect(byId("categoryFilter").config).toEqual({
      allowEmptyOption: true,
      create: false,
      controlInput: null,
    });
    // the placeholder now comes from the select element, translated in the view
    expect(byId("certFilter").config).toEqual({
      plugins: ["remove_button"],
      create: false,
    });
  });

  it("matches the space and category whatever their case", () => {
    byId("spaceFilter").set("sTUDIO");
    expect(visible()).toEqual(["paint"]);
    byId("spaceFilter").set("");
    byId("categoryFilter").set("bUILD");
    expect(visible()).toEqual(["welding"]);
  });

  it("matches the space exactly, not by part of its name", () => {
    byId("spaceFilter").set("Stud");
    expect(visible()).toEqual([]);
  });

  it("matches a certification by part of its name, whatever its case", () => {
    byId("certFilter").set(["weld"]);
    expect(visible()).toEqual(["welding"]);
    byId("certFilter").set(["SAFE"]);
    expect(visible()).toEqual(["welding", "paint"]);
  });

  it("matches the search text anywhere in the card text", () => {
    $("taskSearchInput").value = "the w";
    $("taskSearchInput").dispatchEvent(new Event("input"));
    expect(visible()).toEqual(["paint"]);
    $("taskSearchInput").value = "   ";
    $("taskSearchInput").dispatchEvent(new Event("input"));
    expect(visible()).toEqual(["welding", "paint", "bare"]);
  });

  it("shows a hidden card again once it matches", () => {
    byId("spaceFilter").set("Studio");
    byId("spaceFilter").set("Garage");
    expect(visible()).toEqual(["welding"]);
    expect($("welding").style.display).toBe("");
  });

  it("filters only the cards inside the task index", () => {
    load(`${page}${card("outside", 'data-space="Garage"')}`);
    byId("spaceFilter").set("Studio");
    expect(visible()).toEqual(["paint", "outside"]);
  });

  it("filters by the selects alone on a page without the search box", () => {
    load(`<div id="volunteerTasksIndex">
      <select id="spaceFilter"></select>
      ${card("a", 'data-space="Garage"')}${card("b", 'data-space="Studio"')}
    </div>`);
    expect(selects.map((s) => s.el.id)).toEqual(["spaceFilter"]);
    byId("spaceFilter").set("Garage");
    expect(visible()).toEqual(["a"]);
  });

  it("filters by the search box alone on a page without the selects", () => {
    load(`<div id="volunteerTasksIndex">
      <input id="taskSearchInput">
      ${card("a", 'data-searchable-text="Sweep"')}${card("b", 'data-searchable-text="Mop"')}
    </div>`);
    $("taskSearchInput").value = "mop";
    $("taskSearchInput").dispatchEvent(new Event("input"));
    expect(visible()).toEqual(["b"]);
  });

  it("takes the selected values from selects decorated before the page loaded", () => {
    document.body.innerHTML = page;
    const earlier = {
      getValue: () => "Studio",
      handlers: [],
      on(name, fn) {
        this.handlers.push([name, fn]);
      },
    };
    $("spaceFilter").tomselect = earlier;
    selects.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects.map((s) => s.el.id)).toEqual([
      "categoryFilter",
      "certFilter",
    ]);
    expect(earlier.handlers.map(([name]) => name)).toEqual(["change"]);
    earlier.handlers[0][1]();
    expect(visible()).toEqual(["paint"]);
  });

  it("adds no further handlers when the same decorated page loads again", () => {
    document.dispatchEvent(new Event("turbo:load"));
    expect(byId("spaceFilter").handlers.change).toHaveLength(1);
    expect(byId("categoryFilter").handlers.change).toHaveLength(1);
    expect(byId("certFilter").handlers.change).toHaveLength(1);
    const searches = vi.spyOn($("taskSearchInput"), "addEventListener");
    document.dispatchEvent(new Event("turbo:load"));
    expect(searches).not.toHaveBeenCalled();
  });
});
