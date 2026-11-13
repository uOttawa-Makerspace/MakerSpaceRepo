// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

// The entry file imports every shared script; each has its own tests.
vi.mock("../../../app/javascript/src/validation", () => ({}));
vi.mock("../../../app/javascript/src/direct_uploads", () => ({}));
vi.mock("../../../app/javascript/src/effects", () => ({}));
vi.mock("../../../app/javascript/src/forms", () => ({}));
vi.mock("../../../app/javascript/src/header", () => ({}));
vi.mock("../../../app/javascript/src/photo_gallery", () => ({}));
vi.mock("../../../app/javascript/src/requests", () => ({}));
vi.mock("../../../app/javascript/src/settings", () => ({}));
vi.mock("../../../app/javascript/src/sorting", () => ({}));
vi.mock("../../../app/javascript/src/tabledata", () => ({}));
vi.mock("../../../app/javascript/src/accordion-load", () => ({}));
vi.mock("../../../app/javascript/src/clipboard", () => ({}));
vi.mock("../../../app/javascript/src/theme", () => ({}));
vi.mock("../../../app/javascript/src/calendar_saved", () => ({}));
vi.mock("trix", () => ({}));
vi.mock("@hotwired/turbo-rails", () => ({}));
vi.mock("../../../app/javascript/controllers", () => ({}));

const tooltips = [];
const popovers = [];
vi.mock("bootstrap", () => ({
  Tooltip: class {
    constructor(el) {
      tooltips.push(el);
    }
  },
  Popover: class {
    constructor(el) {
      popovers.push(el);
    }
  },
}));
const toasts = [];
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, options }),
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

await import("../../../app/javascript/entrypoints/application.js");

const $ = (id) => document.getElementById(id);
const load = () => document.dispatchEvent(new Event("turbo:load"));

beforeEach(() => {
  document.body.innerHTML = "";
  tooltips.length = 0;
  popovers.length = 0;
  toasts.length = 0;
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("page load", () => {
  it("flags the scripts as ready", () => {
    expect(document.documentElement.dataset.appJsReady).toBe("true");
  });

  it("starts tooltips and popovers", () => {
    document.body.innerHTML = `<i data-bs-toggle="tooltip"></i><i data-bs-toggle="popover"></i><i data-bs-toggle="popover"></i>`;
    load();
    expect(tooltips).toHaveLength(1);
    expect(popovers).toHaveLength(2);
  });

  it("opens external links in a new tab without leaking the opener", () => {
    document.body.innerHTML = `
      <a id="a" href="https://example.com">x</a>
      <a id="b" href="//cdn.example.com/x">x</a>
      <a id="c" href="/local">x</a>
      <a id="d">no href</a>`;
    load();
    expect($("a").target).toBe("_blank");
    expect($("a").rel).toBe("noopener noreferrer");
    expect($("b").target).toBe("_blank");
    expect($("c").target).toBe("");
    expect($("d").target).toBe("");
  });

  it("turns Turbo off for forms and links that did not opt in", () => {
    document.body.innerHTML = `
      <a id="a" href="/x">x</a>
      <a id="b" href="/x" class="useTurbo" data-turbo="true">x</a>
      <form id="f"></form><form id="g" class="useTurbo"></form>`;
    load();
    expect($("a").dataset.turbo).toBe("false");
    expect($("f").dataset.turbo).toBe("false");
    expect($("b").dataset.turbo).toBe("true");
    expect($("g").dataset.turbo).toBeUndefined();
  });

  it("drops the no-script warning from a page about to be shown", () => {
    const newBody = document.createElement("body");
    newBody.innerHTML = '<div id="noscript-warning"></div><p>keep</p>';
    const event = new Event("turbo:before-render");
    event.detail = { newBody };
    document.dispatchEvent(event);
    expect(newBody.querySelector("#noscript-warning")).toBeNull();
    expect(newBody.querySelector("p")).not.toBeNull();
  });
});

describe("page helpers", () => {
  it("debounce runs the last call after the wait", () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const debounced = window.debounce(fn, 100);
    debounced(1);
    debounced(2);
    vi.advanceTimersByTime(99);
    expect(fn).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith(2);
  });

  it("debounce with immediate runs the first call at once and then waits", () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const debounced = window.debounce(fn, 100, true);
    debounced("a");
    debounced("b");
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith("a");
    vi.advanceTimersByTime(100);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("examResponse posts the chosen answer", async () => {
    const fetchMock = vi.fn(async () => ({}));
    vi.stubGlobal("fetch", fetchMock);
    await window.examResponse(4, 9);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/exam_responses#create");
    expect(init.method).toBe("POST");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(JSON.parse(init.body)).toEqual({ exam_id: 4, answer_id: 9 });
  });

  it("examResponse tells the user when the answer cannot be sent", async () => {
    document.documentElement.dataset.requestNetwork = "Server unreachable";
    toasts.length = 0;
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    await window.examResponse(1, 2);
    expect(toasts).toEqual([
      { message: "Server unreachable", options: { type: "error" } },
    ]);
  });

  it("dragndrop puts the dropped files on the first empty image field", () => {
    document.body.innerHTML = `<input class="image-upload" id="a"><input class="image-upload" id="b">`;
    const taken = { files: { length: 1 } };
    Object.defineProperty($("a"), "files", { value: [1], writable: true });
    Object.defineProperty($("b"), "files", { value: [], writable: true });
    const event = {
      preventDefault: vi.fn(),
      dataTransfer: { files: taken.files },
    };
    window.dragndrop(event);
    expect(event.preventDefault).toHaveBeenCalled();
    expect($("a").files).toEqual([1]);
    expect($("b").files).toBe(taken.files);
  });

  it("dragover allows the drop", () => {
    const event = { preventDefault: vi.fn() };
    window.dragover(event);
    expect(event.preventDefault).toHaveBeenCalled();
  });
});

describe("setSpace", () => {
  const page = '<input id="set_space_id" value="12">';
  const reload = vi.fn();

  beforeEach(() => {
    document.body.innerHTML = page;
    reload.mockClear();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: {
        href: "http://localhost/staff/training_sessions?x=shifts",
        reload,
      },
    });
  });

  const respond = (response) => {
    const fetchMock = vi.fn(async () => response);
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  };

  it("does nothing without the space field", async () => {
    document.body.innerHTML = "";
    const fetchMock = respond({});
    await window.setSpace();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("sends the space and which page it was chosen on, then reloads", async () => {
    const fetchMock = respond({ ok: true, text: async () => "{}" });
    await window.setSpace();
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/staff_dashboard/change_space");
    expect(init.method).toBe("PUT");
    expect(init.credentials).toBe("include");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(JSON.parse(init.body)).toEqual({
      space_id: "12",
      training: true,
      questions: false,
      shifts: true,
    });
    expect(reload).toHaveBeenCalled();
  });

  it("shows the server's error message when the change is refused", async () => {
    respond({
      ok: false,
      text: async () => JSON.stringify({ error: "Not allowed" }),
    });
    await window.setSpace();
    expect(toasts).toEqual([
      { message: "Not allowed", options: { type: "error" } },
    ]);
    expect(reload).not.toHaveBeenCalled();
  });

  it("falls back to a general message when the refusal has no usable body", async () => {
    document.documentElement.dataset.requestFailed = "Could not change space";
    respond({ ok: false, text: async () => "{}" });
    await window.setSpace();
    respond({ ok: false, text: async () => "<html>" });
    await window.setSpace();
    expect(toasts.map((t) => t.message)).toEqual([
      "Could not change space",
      "Could not change space",
    ]);
  });

  it("tells the user when the request fails outright", async () => {
    document.documentElement.dataset.requestNetwork = "Server unreachable";
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    await window.setSpace();
    expect(toasts).toEqual([
      { message: "Server unreachable", options: { type: "error" } },
    ]);
  });
});
