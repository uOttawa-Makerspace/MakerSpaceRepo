// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const sortables = [];
vi.mock("sortablejs", () => ({
  default: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      this.sort = options.sort;
      this.option = vi.fn((name, value) => (this[name] = value));
      sortables.push(this);
    }
  },
}));
const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.config = config;
      selects.push(this);
    }
  },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

const $ = (id) => document.getElementById(id);

async function load(html) {
  document.body.innerHTML = html;
  sortables.length = 0;
  selects.length = 0;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/learning_modules.js");
}

beforeEach(() => {
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("reordering", () => {
  const page = `
    <input type="checkbox" data-order="a" id="switch">
    <div data-order-container="a" id="list">
      <div data-id="3"><span class="sort-handle" hidden></span></div>
      <div data-id="4"><span class="sort-handle" hidden></span></div>
    </div>`;

  it("makes the list sortable only while the switch is on", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    expect(sortables).toHaveLength(1);
    expect(sortables[0].options.sort).toBe(false);
    expect(sortables[0].options.handle).toBe(".sort-handle");

    $("switch").checked = true;
    $("switch").dispatchEvent(new Event("change"));
    expect(sortables[0].option).toHaveBeenCalledWith("sort", true);
    expect(
      [...document.querySelectorAll(".sort-handle")].map((h) => h.hidden),
    ).toEqual([false, false]);

    $("switch").checked = false;
    $("switch").dispatchEvent(new Event("change"));
    expect(
      [...document.querySelectorAll(".sort-handle")].map((h) => h.hidden),
    ).toEqual([true, true]);
  });

  it("saves the new order when a drag ends", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    const fetchMock = vi.fn(async () => ({}));
    vi.stubGlobal("fetch", fetchMock);
    $("list").append($("list").firstElementChild);
    sortables[0].options.onEnd({ from: $("list") });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/learning_area/reorder");
    expect(init.method).toBe("PUT");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(JSON.parse(init.body)).toEqual({ data: ["4", "3"], format: "json" });
  });

  it("logs a failed save", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    sortables[0].options.onEnd({ from: $("list") });
    await vi.waitFor(() =>
      expect(console.error).toHaveBeenCalledWith("Reorder failed:", "offline"),
    );
  });

  it("lets a subskill be chosen or typed", async () => {
    await load('<select id="learning_module_subskill"></select>');
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects[0].config.create).toBe(true);
    expect(selects[0].config.maxItems).toBe(1);
  });
});

describe("new module form", () => {
  const page = `
    <form id="new_learning_module">
      <div><input type="file" id="learning_module_photos"></div>
    </form>`;
  const submit = () => {
    const event = new Event("submit", { cancelable: true });
    $("new_learning_module").dispatchEvent(event);
    return event;
  };

  it("asks for an image when none is chosen, once", async () => {
    await load(page);
    expect(submit().defaultPrevented).toBe(true);
    submit();
    expect($("learning_module_photos").classList.contains("is-invalid")).toBe(
      true,
    );
    expect(document.querySelectorAll(".invalid-feedback")).toHaveLength(1);
    expect(document.querySelector(".invalid-feedback").textContent).toBe(
      "You must upload at least one image",
    );
  });

  it("lets the form go with an image", async () => {
    await load(page);
    Object.defineProperty($("learning_module_photos"), "files", {
      value: [{}],
    });
    expect(submit().defaultPrevented).toBe(false);
  });
});

describe("attachments", () => {
  it("adds another photo row whose button removes it", async () => {
    await load(`<div><div class="row">
      <input type="file"><button id="new-photo-input"><i class="fa fa-plus"></i></button></div></div>`);
    $("new-photo-input").click();
    const rows = document.querySelectorAll(".row");
    expect(rows).toHaveLength(2);
    const added = rows[1].querySelector("button");
    expect(added.id).toBe("");
    expect(added.className).toBe("btn btn-danger");
    expect(added.querySelector("i").className).toBe("fa fa-trash");
    added.click();
    expect(document.querySelectorAll(".row")).toHaveLength(1);
  });

  it("removes an image or a video item", async () => {
    await load(`
      <div class="image-item"><button class="image-remove"></button></div>
      <div class="video-item"><button class="video-remove"></button></div>`);
    document.querySelector(".image-remove").click();
    document.querySelector(".video-remove").click();
    expect(document.querySelector(".image-item")).toBeNull();
    expect(document.querySelector(".video-item")).toBeNull();
  });
});

describe("scorm toggle", () => {
  const page = `
    <input type="checkbox" id="learning_module_scorm_enabled">
    <fieldset id="scorm-section"></fieldset>
    <fieldset id="regular-files-section"></fieldset>`;

  it("shows the package fields for SCORM and the file fields otherwise", async () => {
    await load(page);
    expect($("scorm-section").disabled).toBe(true);
    expect($("scorm-section").style.display).toBe("none");
    expect($("regular-files-section").disabled).toBe(false);

    $("learning_module_scorm_enabled").checked = true;
    $("learning_module_scorm_enabled").dispatchEvent(new Event("change"));
    expect($("scorm-section").disabled).toBe(false);
    expect($("scorm-section").style.display).toBe("");
    expect($("regular-files-section").disabled).toBe(true);
    expect($("regular-files-section").style.display).toBe("none");
  });

  it("is skipped when a section is missing", async () => {
    await load('<input type="checkbox" id="learning_module_scorm_enabled">');
    expect($("learning_module_scorm_enabled")).not.toBeNull();
  });
});

describe("save button", () => {
  const page = `<form id="f"><input required id="r" value="x"><button id="waiting-save-button">Save</button></form>`;
  const submit = () =>
    $("f").dispatchEvent(new Event("submit", { cancelable: true }));

  it("shows a waiting message once a valid form is submitted", async () => {
    vi.useFakeTimers();
    await load(page);
    document.dispatchEvent(new Event("DOMContentLoaded"));
    submit();
    vi.advanceTimersByTime(0);
    expect($("waiting-save-button").disabled).toBe(true);
    expect($("waiting-save-button").innerHTML).toContain(
      "Saving (Please wait)",
    );
  });

  it("leaves the button alone when the form is invalid", async () => {
    vi.useFakeTimers();
    await load(page);
    document.dispatchEvent(new Event("DOMContentLoaded"));
    $("r").value = "";
    submit();
    vi.advanceTimersByTime(0);
    expect($("waiting-save-button").disabled).toBe(false);
  });

  it("copes with a form without the button", async () => {
    await load("<form id='f'></form>");
    document.dispatchEvent(new Event("DOMContentLoaded"));
    expect(submit).not.toThrow();
  });
});
