// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

// A tooltip like Bootstrap's: it moves the title into data-bs-original-title,
// and dispose puts that stored text back as the title.
vi.mock("bootstrap", () => {
  const instances = new Map();
  class Tooltip {
    constructor(el) {
      this.el = el;
      el.setAttribute("data-bs-original-title", el.getAttribute("title"));
      el.removeAttribute("title");
      instances.set(el, this);
    }
    static getInstance(el) {
      return instances.get(el);
    }
    dispose() {
      this.el.setAttribute(
        "title",
        this.el.getAttribute("data-bs-original-title"),
      );
      this.el.removeAttribute("data-bs-original-title");
      instances.delete(this.el);
    }
  }
  return { Tooltip };
});
vi.mock("tom-select", () => ({ default: class {} }));
vi.mock("datatables.net-bs5", () => ({ default: class {} }));
vi.mock("datatables.net-select-bs5", () => ({}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: () => ({}),
}));
const toasts = [];
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

await import("../../../app/javascript/entrypoints/lockers.js");

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function load() {
  document.body.innerHTML = `
    <table>
      <tr><td>
        <input id="note" class="locker-inline-edit" name="locker[notes]" data-locker-id="4" value="x">
      </td></tr>
      <tr><td>
        <select id="size" data-locker-size-for="4" name="locker[locker_size_id]"><option value="2">M</option></select>
        <span class="spinner-border"></span>
      </td></tr>
    </table>`;
  document.dispatchEvent(new Event("turbo:load"));
}

const reply = (status, body) =>
  vi.fn().mockResolvedValue(new Response(JSON.stringify(body), { status }));

describe("locker inline edits", () => {
  beforeEach(() => {
    toasts.length = 0;
    document.documentElement.dataset.requestFailed = "Reload and retry";
    document.documentElement.dataset.requestNetwork = "Unreachable";
    vi.spyOn(console, "error").mockImplementation(() => {});
    load();
  });

  it("shows the server's message when a note is refused", async () => {
    global.fetch = reply(422, {
      error: "The locker could not be saved: Notes too long",
    });
    const note = document.getElementById("note");
    note.dispatchEvent(new Event("change"));
    await flush();
    expect(toasts).toEqual([
      {
        message: "The locker could not be saved: Notes too long",
        type: "error",
      },
    ]);
    expect(note.classList.contains("is-invalid")).toBe(true);
  });

  it("marks a saved note valid and shows nothing", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue(new Response(null, { status: 204 }));
    const note = document.getElementById("note");
    note.dispatchEvent(new Event("change"));
    await flush();
    expect(toasts).toEqual([]);
    expect(note.classList.contains("is-valid")).toBe(true);
  });

  it("shows the server's message when a size change is refused, and hides the spinner", async () => {
    global.fetch = reply(500, {
      error: "Something unexpected went wrong on our side (reference abc12345)",
    });
    const size = document.getElementById("size");
    size.dispatchEvent(new Event("change"));
    await flush();
    expect(toasts[0].message).toContain("reference abc12345");
    expect(size.classList.contains("is-invalid")).toBe(true);
    expect(document.querySelector(".spinner-border").hidden).toBe(true);
  });

  it("shows the translated network text when the connection drops", async () => {
    global.fetch = vi.fn().mockRejectedValue(new TypeError("Failed to fetch"));
    document.getElementById("note").dispatchEvent(new Event("change"));
    await flush();
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });

  it("shows the generic text and request id for an HTML error page", async () => {
    global.fetch = vi.fn(
      async () =>
        new Response("<html></html>", {
          status: 500,
          headers: { "X-Request-Id": "abcdef0123456789" },
        }),
    );
    document.getElementById("note").dispatchEvent(new Event("change"));
    await flush();
    expect(toasts).toEqual([
      { message: "Reload and retry [abcdef01]", type: "error" },
    ]);
  });
});

describe("hover note after a note is saved", () => {
  const hoverTextAfterSaving = async (before, typed) => {
    const { Tooltip } = await import("bootstrap");
    document.body.innerHTML = `
      <div id="wrapper" data-bs-toggle="tooltip" title="${before}">
        <input id="note" class="locker-inline-edit" name="locker[notes]" data-locker-id="4">
      </div>`;
    const wrapper = document.getElementById("wrapper");
    new Tooltip(wrapper);
    document.dispatchEvent(new Event("turbo:load"));
    global.fetch = reply(204, {});
    const note = document.getElementById("note");
    note.value = typed;
    note.dispatchEvent(new Event("change"));
    await flush();
    return Tooltip.getInstance(wrapper).el.getAttribute(
      "data-bs-original-title",
    );
  };

  it("shows the new note", async () => {
    expect(await hoverTextAfterSaving("Placeholder", "Door sticks")).toBe(
      "Door sticks",
    );
  });

  it("shows the placeholder once the note is cleared", async () => {
    expect(await hoverTextAfterSaving("Old note", "")).toBe("No note");
  });
});
