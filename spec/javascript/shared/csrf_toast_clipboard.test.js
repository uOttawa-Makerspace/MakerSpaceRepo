// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const shows = [];
const options = [];
vi.mock("bootstrap", () => ({
  Toast: {
    getOrCreateInstance: (el, opts) => {
      options.push(opts);
      return { show: () => shows.push(el) };
    },
  },
}));

const { csrfToken, csrfParam, csrfHeaders } =
  await import("../../../app/javascript/src/csrf.js");
const { showToast } = await import("../../../app/javascript/src/toast.js");
await import("../../../app/javascript/src/clipboard.js");

beforeEach(() => {
  document.head.innerHTML = "";
  document.body.innerHTML = "";
  shows.length = 0;
  options.length = 0;
});

describe("csrf", () => {
  it("reads the token and parameter name from the page", () => {
    document.head.innerHTML =
      '<meta name="csrf-token" content="abc"><meta name="csrf-param" content="my_param">';
    expect(csrfToken()).toBe("abc");
    expect(csrfParam()).toBe("my_param");
    expect(csrfHeaders({ Accept: "x" })).toEqual({
      Accept: "x",
      "X-CSRF-Token": "abc",
    });
  });

  it("falls back to an empty token and the default parameter", () => {
    expect(csrfToken()).toBe("");
    expect(csrfParam()).toBe("authenticity_token");
    expect(csrfHeaders()).toEqual({ "X-CSRF-Token": "" });
  });
});

describe("toast", () => {
  const toasts = () => [...document.querySelectorAll(".toast")];

  it("shows a message in a container it creates once", () => {
    showToast("Saved", { type: "success" });
    showToast("Again");
    expect(document.querySelectorAll("#toast-container")).toHaveLength(1);
    expect(toasts()).toHaveLength(2);
    expect(toasts()[0].classList.contains("text-bg-success")).toBe(true);
    expect(toasts()[0].querySelector(".toast-body").textContent).toBe("Saved");
    expect(toasts()[0].getAttribute("role")).toBe("alert");
    expect(shows).toHaveLength(2);
    expect(options[0]).toEqual({ delay: 5000 });
  });

  it("styles an error and falls back to info for an unknown type", () => {
    showToast("Bad", { type: "error" });
    showToast("Odd", { type: "weird" });
    expect(toasts()[0].classList.contains("text-bg-danger")).toBe(true);
    expect(toasts()[1].classList.contains("text-bg-primary")).toBe(true);
  });

  it("treats the message as text, not markup", () => {
    showToast("<b>bold</b>");
    expect(document.querySelector(".toast-body b")).toBeNull();
    expect(document.querySelector(".toast-body").textContent).toBe(
      "<b>bold</b>",
    );
  });

  it("adds a link after the message", () => {
    showToast("Done", { link: { text: "View", href: "/x" } });
    const a = document.querySelector(".toast-body a");
    expect(a.textContent).toBe("View");
    expect(a.getAttribute("href")).toBe("/x");
  });

  it("has a close button and removes itself when hidden", () => {
    showToast("Hi");
    const el = toasts()[0];
    expect(el.querySelector("[data-bs-dismiss=toast]")).not.toBeNull();
    el.dispatchEvent(new Event("hidden.bs.toast"));
    expect(toasts()).toHaveLength(0);
  });

  it("shows a toast for the page wide toast:show event", () => {
    document.dispatchEvent(
      new CustomEvent("toast:show", {
        detail: { message: "From server", type: "error" },
      }),
    );
    expect(toasts()[0].textContent).toContain("From server");
    expect(toasts()[0].classList.contains("text-bg-danger")).toBe(true);
  });
});

describe("clipboard", () => {
  let writeText;
  beforeEach(() => {
    writeText = vi.fn(() => Promise.resolve());
    vi.stubGlobal("navigator", { ...navigator, clipboard: { writeText } });
  });

  it("copies the button's own text", () => {
    document.body.innerHTML =
      '<button class="clipboard-btn" data-clipboard-text="hello"><i id="icon"></i></button>';
    document
      .getElementById("icon")
      .dispatchEvent(new Event("click", { bubbles: true }));
    expect(writeText).toHaveBeenCalledWith("hello");
  });

  it("copies the value of an input or the text of another element", () => {
    document.body.innerHTML = `
      <input id="field" value="from input">
      <p id="para">from text</p>
      <button class="clipboard-btn" id="a" data-clipboard-target="#field"></button>
      <button class="clipboard-btn" id="b" data-clipboard-target="#para"></button>`;
    document.getElementById("a").click();
    document.getElementById("b").click();
    expect(writeText.mock.calls).toEqual([["from input"], ["from text"]]);
  });

  it("does nothing when the target is missing or the click is elsewhere", () => {
    document.body.innerHTML =
      '<button class="clipboard-btn" id="a" data-clipboard-target="#nope"></button><p id="p"></p>';
    document.getElementById("a").click();
    document.getElementById("p").click();
    expect(writeText).not.toHaveBeenCalled();
  });

  it("does nothing without clipboard support", () => {
    vi.stubGlobal("navigator", { ...navigator, clipboard: undefined });
    document.body.innerHTML =
      '<button class="clipboard-btn" data-clipboard-text="x"></button>';
    expect(() => document.querySelector("button").click()).not.toThrow();
  });

  it("copyField shows Copied! and restores the label", async () => {
    vi.useFakeTimers();
    document.body.innerHTML =
      '<span id="code">ABC123</span><button id="b">Copy</button>';
    const btn = document.getElementById("b");
    window.copyField("#code", btn);
    await vi.advanceTimersByTimeAsync(0);
    expect(writeText).toHaveBeenCalledWith("ABC123");
    expect(btn.textContent).toBe("Copied!");
    vi.advanceTimersByTime(2000);
    expect(btn.textContent).toBe("Copy");
    vi.useRealTimers();
  });

  it("copyField says Failed when copying is refused", async () => {
    writeText.mockReturnValue(Promise.reject(new Error("no")));
    document.body.innerHTML =
      '<span id="code">A</span><button id="b">Copy</button>';
    const btn = document.getElementById("b");
    window.copyField("#code", btn);
    await Promise.resolve();
    await Promise.resolve();
    expect(btn.textContent).toBe("Failed");
  });
});
