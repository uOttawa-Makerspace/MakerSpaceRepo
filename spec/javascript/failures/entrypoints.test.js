// @vitest-environment happy-dom
// What the pages' scripts tell the user when a request fails: the server's reason, or the page's translated text
// with the request reference; never silence and never the browser's own message.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { answerWith, dropConnection, flush, reset, toasts } from "./support.js";

vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("tom-select", () => ({ default: class {} }));
vi.mock("sortablejs", () => ({
  default: class {
    constructor(_element, options) {
      globalThis.sortableOptions = options;
    }
    destroy() {}
    option() {}
  },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

const SERVER_FAILURE = { error: "Not allowed", reference: "ab12cd34" };

beforeEach(async () => {
  reset();
  vi.resetModules();
});

describe("certification file upload (users.js)", () => {
  async function upload() {
    document.body.innerHTML = `
      <form id="cert_form" action="/users/1"></form>
      <input id="cert" class="key-cert-file" type="file">
      <div id="cert_show"></div><div id="cert_hide" style="display:none"></div>`;
    const input = document.getElementById("cert");
    Object.defineProperty(input, "files", {
      value: [{ type: "application/pdf" }],
    });
    await import("../../../app/javascript/entrypoints/users.js");
    document.dispatchEvent(new Event("turbo:load"));
    input.dispatchEvent(new Event("change"));
    await flush();
  }

  it("shows the server's reason when the upload is refused", async () => {
    global.fetch = answerWith(403, SERVER_FAILURE);
    await upload();
    expect(toasts).toEqual([
      { message: "Not allowed [ab12cd34]", type: "error" },
    ]);
    expect(document.getElementById("cert_hide").style.display).toBe("none");
  });

  it("shows the translated network text when the connection drops", async () => {
    global.fetch = dropConnection();
    await upload();
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });

  it("swaps the upload field for the link when the upload is saved", async () => {
    global.fetch = answerWith(200, {});
    await upload();
    expect(toasts).toEqual([]);
    expect(document.getElementById("cert_hide").style.display).toBe("block");
  });
});

describe("learning module reorder (learning_modules.js)", () => {
  async function reorder() {
    document.body.innerHTML = `
      <input type="checkbox" data-order="m">
      <div data-order-container="m"><div data-id="1"></div><div data-id="2"></div></div>`;
    await import("../../../app/javascript/entrypoints/learning_modules.js");
    document.dispatchEvent(new Event("turbo:load"));
    globalThis.sortableOptions.onEnd({
      from: document.querySelector("[data-order-container]"),
    });
    await flush();
  }

  it("says why the order was not saved", async () => {
    global.fetch = answerWith(404, { error: "Module is gone" });
    await reorder();
    expect(toasts).toEqual([{ message: "Module is gone", type: "error" }]);
  });

  it("shows the generic text and request id when the answer has no reason", async () => {
    global.fetch = answerWith(400, "", { "X-Request-Id": "0123456789abcdef" });
    await reorder();
    expect(toasts).toEqual([
      { message: "Reload and retry [01234567]", type: "error" },
    ]);
  });

  it("shows nothing when the order is saved", async () => {
    global.fetch = answerWith(200, { status: "ok" });
    await reorder();
    expect(toasts).toEqual([]);
  });
});

describe("FAQ reorder (faqs.js)", () => {
  async function reorder() {
    document.body.innerHTML = `
      <input type="checkbox" id="reorderSwitch">
      <div id="faqAccordion"><div data-faq-id="1"></div></div>`;
    await import("../../../app/javascript/entrypoints/faqs.js");
    document.dispatchEvent(new Event("turbo:load"));
    const toggle = document.getElementById("reorderSwitch");
    toggle.checked = true;
    toggle.dispatchEvent(new Event("change"));
    globalThis.sortableOptions.onSort({
      to: document.getElementById("faqAccordion"),
    });
    await flush();
  }

  it("says why the order was not saved", async () => {
    global.fetch = answerWith(403, SERVER_FAILURE);
    await reorder();
    expect(toasts).toEqual([
      { message: "Not allowed [ab12cd34]", type: "error" },
    ]);
  });

  it("shows the translated network text when the connection drops", async () => {
    global.fetch = dropConnection();
    await reorder();
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });
});

describe("acquired badge text (generate_acquired_badge.js)", () => {
  async function load(fetchMock) {
    global.fetch = fetchMock;
    document.body.innerHTML = `
      <input id="training_id_field" value="3"><input id="training_level_field" value="Gold">
      <div id="badge-acquired-text"></div>`;
    await import("../../../app/javascript/entrypoints/generate_acquired_badge.js");
    await flush();
  }

  it("inserts the server's text as text, never as markup", async () => {
    await load(answerWith(200, "<img src=x onerror=alert(1)> - Gold"));
    const container = document.getElementById("badge-acquired-text");
    expect(container.querySelector("img")).toBeNull();
    expect(container.textContent).toBe("<img src=x onerror=alert(1)> - Gold");
  });

  it("tells the user when the text could not be loaded", async () => {
    await load(answerWith(500, "<html></html>"));
    expect(toasts).toEqual([{ message: "Reload and retry", type: "error" }]);
    expect(document.getElementById("badge-acquired-text").textContent).toBe("");
  });

  it("shows the translated network text when the connection drops", async () => {
    await load(dropConnection());
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });
});

describe("volunteer request search (volunteer_task_requests.js)", () => {
  async function search(fetchMock) {
    vi.useFakeTimers();
    global.fetch = fetchMock;
    document.body.innerHTML = `
      <div id="volunteerTaskRequestsIndex">
        <input id="search_pending"><input id="search_processed">
        <div class="pending-requests">old</div><div class="processed-requests">old</div>
      </div>`;
    await import("../../../app/javascript/entrypoints/volunteer_task_requests.js");
    document.dispatchEvent(new Event("turbo:load"));
    document.getElementById("search_pending").dispatchEvent(new Event("input"));
    document
      .getElementById("search_processed")
      .dispatchEvent(new Event("input"));
    await vi.advanceTimersByTimeAsync(400);
    vi.useRealTimers();
    await flush();
  }

  it("shows the search results the server renders", async () => {
    await search(answerWith(200, "<p>new</p>"));
    expect(document.querySelector(".pending-requests").innerHTML).toBe(
      "<p>new</p>",
    );
    expect(toasts).toEqual([]);
  });

  it("keeps the old list and says why when a search fails", async () => {
    await search(answerWith(500, "<html></html>"));
    expect(document.querySelector(".pending-requests").textContent).toBe("old");
    expect(toasts.map((t) => t.message)).toEqual([
      "Reload and retry",
      "Reload and retry",
    ]);
  });
});

describe("staff picker search (add_new_staff.js)", () => {
  async function load(fetchMock) {
    global.fetch = fetchMock;
    let options;
    vi.doMock("tom-select", () => ({
      default: class {
        constructor(_el, opts) {
          options = opts;
        }
      },
    }));
    document.body.innerHTML = '<select id="new_staff_select"></select>';
    await import("../../../app/javascript/entrypoints/add_new_staff.js");
    const callback = vi.fn();
    options.load("ab", callback);
    await flush();
    return callback;
  }

  it("hands the matching people to the picker", async () => {
    const callback = await load(
      answerWith(200, { users: [{ username: "ab", name: "Abe" }] }),
    );
    expect(callback).toHaveBeenCalledWith([{ id: "ab", name: "Abe" }]);
    expect(toasts).toEqual([]);
  });

  it("empties the picker and says why when the search fails", async () => {
    const callback = await load(answerWith(401, SERVER_FAILURE));
    expect(callback).toHaveBeenCalledWith();
    expect(toasts).toEqual([
      { message: "Not allowed [ab12cd34]", type: "error" },
    ]);
  });

  it("treats an answer without a JSON body as a failure", async () => {
    const callback = await load(answerWith(200, "<html></html>"));
    expect(callback).toHaveBeenCalledWith();
    expect(toasts).toEqual([{ message: "Reload and retry", type: "error" }]);
  });
});

describe("copy buttons (clipboard.js)", () => {
  const clipboard = (writeText) =>
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: writeText && { writeText },
    });

  async function click() {
    document.body.innerHTML =
      '<button class="clipboard-btn" data-clipboard-text="hi">Copy</button>';
    await import("../../../app/javascript/src/clipboard.js");
    document
      .querySelector(".clipboard-btn")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await flush();
  }

  it("copies without a message when the browser allows it", async () => {
    const writeText = vi.fn().mockResolvedValue();
    clipboard(writeText);
    await click();
    expect(writeText).toHaveBeenCalledWith("hi");
    expect(toasts).toEqual([]);
  });

  it("says the text could not be copied when the browser refuses", async () => {
    clipboard(vi.fn().mockRejectedValue(new Error("denied")));
    await click();
    expect(toasts).toEqual([{ message: "Copy by hand", type: "error" }]);
  });

  it("says so when the page has no clipboard at all", async () => {
    clipboard(undefined);
    await click();
    expect(toasts).toEqual([{ message: "Copy by hand", type: "error" }]);
  });

  it("copyField reports a refused copy instead of rewriting the button", async () => {
    clipboard(vi.fn().mockRejectedValue(new Error("denied")));
    document.body.innerHTML =
      '<span id="f">x</span><button id="b">Copy</button>';
    await import("../../../app/javascript/src/clipboard.js");
    window.copyField("#f", document.getElementById("b"));
    await flush();
    expect(document.getElementById("b").textContent).toBe("Copy");
    expect(toasts).toEqual([{ message: "Copy by hand", type: "error" }]);
  });
});

describe("SCORM commits (scorm_commit_service.js)", () => {
  async function commit(xhr) {
    globalThis.XMLHttpRequest = class {
      open() {}
      setRequestHeader() {}
      getResponseHeader(name) {
        return xhr.headers?.[name] ?? null;
      }
      send() {
        if (xhr.throws) throw new Error("NetworkError");
      }
      get status() {
        return xhr.status;
      }
      get responseText() {
        return xhr.body ?? "";
      }
    };
    const { ScormCommitService } =
      await import("../../../app/javascript/src/scorm_commit_service.js");
    return new ScormCommitService({ commitFailureCode: 391 }).post("/c", {});
  }

  it("shows nothing when the commit is stored", async () => {
    expect(await commit({ status: 200 })).toEqual({
      result: "true",
      errorCode: 0,
    });
    expect(toasts).toEqual([]);
  });

  it("tells the learner the server's reason and still fails the commit for the module", async () => {
    const result = await commit({
      status: 422,
      body: JSON.stringify({ error: "SCORM package not ready" }),
    });
    expect(result).toEqual({ result: "false", errorCode: 391 });
    expect(toasts).toEqual([
      { message: "SCORM package not ready", type: "error" },
    ]);
  });

  it("shows the generic text with the request reference for an answer without a reason", async () => {
    await commit({
      status: 500,
      body: "<html>",
      headers: { "X-Request-Id": "0123456789abcdef" },
    });
    expect(toasts).toEqual([
      { message: "Reload and retry [01234567]", type: "error" },
    ]);
  });

  it("shows the translated network text when the commit cannot be sent", async () => {
    const result = await commit({ throws: true });
    expect(result).toEqual({ result: "false", errorCode: 391 });
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });
});
