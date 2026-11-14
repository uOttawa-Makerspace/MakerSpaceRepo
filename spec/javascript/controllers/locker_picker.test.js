// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const instances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(element, options) {
      this.element = element;
      this.options = options;
      this.destroy = vi.fn();
      element.tomselect = this;
      instances.push(this);
    }
  },
}));

const { default: LockerPicker } =
  await import("../../../app/javascript/controllers/locker-picker_controller.js");

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(html) {
  document.body.innerHTML = html;
  application = Application.start();
  application.register("locker-picker", LockerPicker);
  await settle();
}

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  instances.length = 0;
});

const form = (id, extra = "") => `
  <form data-controller="locker-picker">
    <select id="${id}" data-locker-picker-target="locker"></select>
    ${extra}
  </form>`;

describe("locker-picker", () => {
  it("makes the locker select of its own form searchable, one pick at a time", async () => {
    await mount(form("locker_a"));
    expect(instances).toHaveLength(1);
    expect(instances[0].element.id).toBe("locker_a");
    expect(instances[0].options).toMatchObject({ create: false, maxItems: 1 });
  });

  it("leaves a second form's select to its own controller, with no shared id", async () => {
    await mount(form("locker_checkout") + form("locker_assign"));
    expect(instances.map((i) => i.element.id)).toEqual([
      "locker_checkout",
      "locker_assign",
    ]);
  });

  it("ignores selects outside a locker-picker form", async () => {
    await mount(`<select id="outside"></select>${form("locker_a")}`);
    expect(instances.map((i) => i.element.id)).toEqual(["locker_a"]);
  });

  it("does not wrap a select that is already searchable", async () => {
    document.body.innerHTML = form("locker_a");
    document.getElementById("locker_a").tomselect = { destroy: vi.fn() };
    application = Application.start();
    application.register("locker-picker", LockerPicker);
    await settle();
    expect(instances).toHaveLength(0);
  });

  it("replaces the copied pickers of its selects on a page restored from the cache", async () => {
    await mount(`
      <form data-controller="locker-picker">
        <select id="locker_a" class="form-select tomselected ts-hidden-accessible" tabindex="-1" data-locker-picker-target="locker"></select><div class="ts-wrapper"></div>
        <select id="user" class="tomselected ts-hidden-accessible" tabindex="-1" data-locker-picker-target="user"></select><div class="ts-wrapper"></div>
      </form>`);
    expect(document.querySelectorAll(".ts-wrapper")).toHaveLength(0);
    expect(document.querySelectorAll(".tomselected")).toHaveLength(0);
    expect(document.getElementById("locker_a").className).toBe("form-select");
    expect(instances.map((i) => i.element.id)).toEqual(["locker_a", "user"]);
  });

  it("leaves the copied picker of a select outside its form alone", async () => {
    await mount(
      `<select id="outside" class="tomselected"></select><div class="ts-wrapper" id="outside-copy"></div>${form("locker_a")}`,
    );
    expect(document.getElementById("outside-copy")).not.toBeNull();
    expect(document.getElementById("outside").className).toBe("tomselected");
  });

  it("makes the user select searchable by name or username", async () => {
    await mount(
      form(
        "locker_a",
        `<select id="user" data-locker-picker-target="user"></select>`,
      ),
    );
    const user = instances.find((i) => i.element.id === "user");
    expect(user.options).toMatchObject({ searchField: ["text"], maxItems: 1 });
  });

  it("renders a locker line with its size and a staff-only note", async () => {
    await mount(form("locker_a"));
    const { option, item } = instances[0].options.render;
    const escape = (text) => text.replace(/</g, "&lt;");
    const html = option(
      { text: "#301", size: "12x12", staffOnly: "true" },
      escape,
    );
    expect(html).toBe("<div>Locker #301 - Size 12x12 - Staff only</div>");
    expect(item({ text: "<b>" }, escape)).toBe(
      "<div>Locker &lt;b> - Size </div>",
    );
  });

  it("renders a user line with a role badge only for staff", async () => {
    await mount(
      form(
        "locker_a",
        `<select id="user" data-locker-picker-target="user"></select>`,
      ),
    );
    const { option, item } = instances.find((i) => i.element.id === "user")
      .options.render;
    const escape = (text) => text;
    expect(option({ text: "Sam", role: "Staff" }, escape)).toContain(
      "badge text-bg-primary ms-2",
    );
    expect(item({ text: "Sam" }, escape)).toBe("<div>Sam</div>");
  });

  it("destroys its pickers when the form leaves the page", async () => {
    await mount(
      form(
        "locker_a",
        `<select id="user" data-locker-picker-target="user"></select>`,
      ),
    );
    document.body.innerHTML = "";
    await settle();
    expect(instances).toHaveLength(2);
    instances.forEach((picker) =>
      expect(picker.destroy).toHaveBeenCalledTimes(1),
    );
  });
});
