// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const sortables = [];
vi.mock("sortablejs", () => ({
  default: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      sortables.push(this);
    }
  },
}));

await import("../../../app/javascript/entrypoints/design_days.js");

const $ = (id) => document.getElementById(id);
const load = (html) => {
  document.body.innerHTML = html;
  sortables.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
};

const FLOORPLAN = `<div data-floorplan-container></div>
  <button data-floorplan-add></button>
  <div data-floorplan-template><input type="file"><button data-floorplan-delete></button></div>`;

beforeEach(() => {
  vi.spyOn(console, "log").mockImplementation(() => {});
});

describe("spreadsheet key", () => {
  const KEY = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"; // 44 characters
  const page = `
    <input id="design_day_sheet_key">
    <button id="verifyDesignDaySheet"></button>
    <div id="sheet_key_may_be_invalid" hidden></div>
    <a id="sheet_key_preview_url"></a>
    <i id="sheet_key_verified_icon" hidden></i>
    <i id="sheet_key_maybe_icon" hidden></i>
    <i id="sheet_key_error_icon" hidden></i>
    ${FLOORPLAN}`;

  const status = () =>
    ["verified", "maybe", "error"].filter(
      (name) => !$(`sheet_key_${name}_icon`).hidden,
    );
  const verify = (value) => {
    $("design_day_sheet_key").value = value;
    const event = new Event("click", { cancelable: true });
    $("verifyDesignDaySheet").dispatchEvent(event);
    return event;
  };

  it("takes the key out of a pasted sheet address", () => {
    load(page);
    const event = verify(
      `https://docs.google.com/spreadsheets/d/${KEY}/edit?gid=0#gid=0`,
    );
    expect(event.defaultPrevented).toBe(true);
    expect($("design_day_sheet_key").value).toBe(KEY);
    expect($("sheet_key_preview_url").href).toBe(
      `https://docs.google.com/spreadsheets/d/${KEY}`,
    );
    expect($("sheet_key_may_be_invalid").hidden).toBe(true);
    expect(status()).toEqual(["verified"]);
  });

  it("flags a value with no key in it and previews what was typed", () => {
    load(page);
    verify("too short");
    expect($("sheet_key_may_be_invalid").hidden).toBe(false);
    expect(status()).toEqual(["error"]);
    expect($("sheet_key_preview_url").textContent).toBe(
      "https://docs.google.com/spreadsheets/d/too short",
    );
  });

  it("marks the key as unchecked while typing", () => {
    load(page);
    const input = $("design_day_sheet_key");
    input.dispatchEvent(
      Object.assign(new Event("input"), { inputType: "insertText" }),
    );
    expect(status()).toEqual(["maybe"]);
    expect($("sheet_key_preview_url").textContent).toBe("");
  });

  it("checks the key at once when it is pasted", () => {
    load(page);
    const input = $("design_day_sheet_key");
    input.value = KEY;
    input.dispatchEvent(
      Object.assign(new Event("input"), { inputType: "insertFromPaste" }),
    );
    expect(status()).toEqual(["verified"]);
  });

  it("does nothing on a page without the key field", () => {
    load(FLOORPLAN);
    expect($("design_day_sheet_key")).toBeNull();
  });
});

describe("repeating fields", () => {
  const page = `
    <fieldset id="tpl" disabled hidden>
      <input class="ordering-attribute" name="design_day[items][TEMPLATE][ordering]" id="item_TEMPLATE_ordering">
      <label for="item_TEMPLATE_ordering">TEMPLATE label</label>
      <input type="checkbox" data-delete-template>
    </fieldset>
    <input class="ordering-attribute" id="existing" value="5">
    <button data-template-fields="#tpl" id="add"></button>
    ${FLOORPLAN}`;

  it("adds a copy of the template with a unique name before the button", () => {
    load(page);
    const click = new Event("click", { cancelable: true });
    $("add").dispatchEvent(click);
    expect(click.defaultPrevented).toBe(true);

    const copy = $("add").previousElementSibling;
    expect(copy.tagName).toBe("FIELDSET");
    expect(copy.hasAttribute("id")).toBe(false);
    expect(copy.hidden).toBe(false);
    expect(copy.hasAttribute("disabled")).toBe(false);
    const input = copy.querySelector("input.ordering-attribute");
    expect(input.name).not.toContain("TEMPLATE");
    expect(input.name).toMatch(/\[items\]\[\d+\]\[ordering\]/);
    expect(input.id).not.toContain("TEMPLATE");
    expect(copy.querySelector("label").htmlFor).toBe(input.id);
    // only attributes are renamed, never text
    expect(copy.querySelector("label").textContent).toBe("TEMPLATE label");
  });

  it("numbers every ordering field in page order after adding one", () => {
    load(page);
    $("add").click();
    const values = [
      ...document.querySelectorAll("input.ordering-attribute"),
    ].map((i) => i.value);
    expect(values).toEqual(["0", "1", "2"]);
  });

  it("hides a field whose delete box is ticked", () => {
    load(page);
    $("add").click();
    const copy = $("add").previousElementSibling;
    const box = copy.querySelector("[data-delete-template]");
    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(copy.hidden).toBe(true);
  });

  it("keeps a field visible when the box is unticked", () => {
    load(
      `<fieldset><input type="checkbox" data-delete-template id="d"></fieldset>${FLOORPLAN}`,
    );
    $("d").dispatchEvent(new Event("change"));
    expect($("d").closest("fieldset").hidden).toBe(false);
    $("d").checked = true;
    $("d").dispatchEvent(new Event("change"));
    expect($("d").closest("fieldset").hidden).toBe(true);
  });
});

describe("schedule sorting", () => {
  const page = `
    <ul class="design-day-schedule-sort-list" data-event-for="morning" id="morning">
      <li id="a"><input class="event-for-attribute" value="morning"><input class="ordering-attribute"></li>
    </ul>
    <ul class="design-day-schedule-sort-list" data-event-for="afternoon" id="afternoon">
      <li id="b"><input class="event-for-attribute" value="afternoon"><input class="ordering-attribute"></li>
    </ul>
    ${FLOORPLAN}`;

  it("makes each list sortable within one shared group", () => {
    load(page);
    expect(sortables).toHaveLength(2);
    expect(sortables.map((s) => s.options.group)).toEqual([
      "design_day_schedule",
      "design_day_schedule",
    ]);
    expect(sortables[0].options.handle).toBe(".sort-handle");
  });

  it("numbers the schedules when the page loads", () => {
    load(page);
    expect(
      [...document.querySelectorAll("input.ordering-attribute")].map(
        (i) => i.value,
      ),
    ).toEqual(["0", "1"]);
  });

  it("moves a dragged schedule to its new part of the day and renumbers", () => {
    load(page);
    const item = $("a");
    $("afternoon").prepend(item);
    sortables[0].options.onSort({ to: $("afternoon"), item });

    expect(item.querySelector("input.event-for-attribute").value).toBe(
      "afternoon",
    );
    expect(
      [...document.querySelectorAll("input.ordering-attribute")].map(
        (i) => i.value,
      ),
    ).toEqual(["0", "1"]);
  });
});

describe("floorplans", () => {
  it("adds a floorplan input from the template", () => {
    load(FLOORPLAN);
    const event = new Event("click", { cancelable: true });
    document.querySelector("[data-floorplan-add]").dispatchEvent(event);
    document.querySelector("[data-floorplan-add]").click();
    expect(event.defaultPrevented).toBe(true);
    expect(
      document.querySelectorAll("[data-floorplan-container] input[type=file]"),
    ).toHaveLength(2);
  });

  it("removes a floorplan input with its delete button, existing or new", () => {
    load(`<div data-floorplan-container>
        <div id="old"><input type="file"><button data-floorplan-delete id="del"></button></div>
      </div>
      <button data-floorplan-add></button>
      <div data-floorplan-template><input type="file"><button data-floorplan-delete></button></div>`);
    const event = new Event("click", { cancelable: true });
    $("del").dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    expect($("old")).toBeNull();

    document.querySelector("[data-floorplan-add]").click();
    document
      .querySelector("[data-floorplan-container] [data-floorplan-delete]")
      .click();
    expect(
      document.querySelector("[data-floorplan-container]").children,
    ).toHaveLength(0);
  });
});
