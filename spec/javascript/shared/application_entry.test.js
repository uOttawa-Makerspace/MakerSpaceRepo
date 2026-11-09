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

describe("confirmations", () => {
  let confirm;
  beforeEach(() => {
    confirm = vi.fn(() => false);
    vi.stubGlobal("confirm", confirm);
  });

  const submit = (form, submitter) => {
    const event = new Event("submit", { bubbles: true, cancelable: true });
    event.submitter = submitter;
    form.dispatchEvent(event);
    return event;
  };

  it("asks before a legacy data-confirm form is submitted and stops it on cancel", () => {
    document.body.innerHTML = '<form id="f" data-confirm="Sure?"></form>';
    const event = submit($("f"));
    expect(confirm).toHaveBeenCalledWith("Sure?");
    expect(event.defaultPrevented).toBe(true);
  });

  it("lets the submit through when confirmed", () => {
    confirm.mockReturnValue(true);
    document.body.innerHTML = '<form id="f" data-confirm="Sure?"></form>';
    expect(submit($("f")).defaultPrevented).toBe(false);
  });

  it("prefers the submit button's message over the form's", () => {
    document.body.innerHTML = `<form id="f" data-confirm="Form"><button id="b" data-confirm="Button"></button></form>`;
    submit($("f"), $("b"));
    expect(confirm).toHaveBeenCalledWith("Button");
  });

  it("does not ask for a form with no message", () => {
    document.body.innerHTML = '<form id="f"></form>';
    expect(submit($("f")).defaultPrevented).toBe(false);
    expect(confirm).not.toHaveBeenCalled();
  });

  it("leaves a data-turbo-confirm prompt to Turbo while Turbo handles the form", () => {
    document.body.innerHTML =
      '<form id="f" class="useTurbo" data-turbo-confirm="Turbo?"></form>';
    expect(submit($("f")).defaultPrevented).toBe(false);
    expect(confirm).not.toHaveBeenCalled();
  });

  it("asks itself for a data-turbo-confirm form that Turbo is off for, and turns Turbo off", () => {
    document.body.innerHTML =
      '<form id="f" data-turbo-confirm="Turbo?"></form>';
    const event = submit($("f"));
    expect(confirm).toHaveBeenCalledWith("Turbo?");
    expect(event.defaultPrevented).toBe(true);
    expect($("f").dataset.turbo).toBe("false");
  });

  it("does not turn Turbo off for the hidden forms Turbo builds itself", () => {
    document.body.innerHTML =
      '<form id="f" data-turbo="true" data-confirm="Sure?"></form>';
    submit($("f"));
    expect($("f").dataset.turbo).toBe("true");
  });

  const click = (el) => {
    const event = new Event("click", { bubbles: true, cancelable: true });
    el.dispatchEvent(event);
    return event;
  };

  it("asks before a data-confirm link is followed and stops it on cancel", () => {
    document.body.innerHTML =
      '<a id="l" href="/x" data-confirm="Go?"><i id="i"></i></a>';
    const event = click($("i"));
    expect(confirm).toHaveBeenCalledWith("Go?");
    expect(event.defaultPrevented).toBe(true);
  });

  it("leaves the prompt of a Turbo method link to Turbo", () => {
    document.body.innerHTML =
      '<a id="l" href="/x" class="useTurbo" data-turbo-method="delete" data-turbo-confirm="Del?"></a>';
    expect(click($("l")).defaultPrevented).toBe(false);
    expect(confirm).not.toHaveBeenCalled();
  });

  it("prompts for a Turbo link without a method, which Turbo does not", () => {
    document.body.innerHTML =
      '<a id="l" href="/x" class="useTurbo" data-turbo-confirm="Go?"></a>';
    expect(click($("l")).defaultPrevented).toBe(true);
    expect(confirm).toHaveBeenCalledWith("Go?");
  });

  it("ignores clicks that are not on a confirming link", () => {
    document.body.innerHTML = '<a id="l" href="/x"></a><p id="p"></p>';
    click($("l"));
    click($("p"));
    click(document);
    expect(confirm).not.toHaveBeenCalled();
  });
});

describe("page helpers", () => {
  it("clearEndDate empties the field and tolerates its absence", () => {
    document.body.innerHTML = '<input id="end_date" value="2026-01-01">';
    window.clearEndDate();
    expect($("end_date").value).toBe("");
    document.body.innerHTML = "";
    expect(() => window.clearEndDate()).not.toThrow();
  });

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

  it("examResponse logs a failed post", async () => {
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    await window.examResponse(1, 2);
    expect(console.error).toHaveBeenCalledWith(
      "Exam response error:",
      expect.any(Error),
    );
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
    const fetchMock = respond({ ok: true });
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
    respond({ ok: false, json: async () => ({ error: "Not allowed" }) });
    await window.setSpace();
    expect(toasts).toEqual([
      { message: "Not allowed", options: { type: "error" } },
    ]);
    expect(reload).not.toHaveBeenCalled();
  });

  it("falls back to a general message when the refusal has no usable body", async () => {
    respond({ ok: false, json: async () => ({}) });
    await window.setSpace();
    respond({
      ok: false,
      json: async () => {
        throw new Error("html");
      },
    });
    await window.setSpace();
    expect(toasts.map((t) => t.message)).toEqual([
      "Could not change space",
      "Could not change space",
    ]);
  });

  it("logs a request that fails outright", async () => {
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    await window.setSpace();
    expect(console.error).toHaveBeenCalledWith(
      "Failed to update space:",
      expect.any(Error),
    );
  });
});
