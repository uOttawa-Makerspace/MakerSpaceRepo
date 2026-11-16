// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  oncePerElement,
  onEveryPageLoad,
  onPageLoad,
} from "../../../app/javascript/src/on_page.js";

const handler = vi.fn();
onPageLoad("#root", handler);

afterEach(() => {
  handler.mockClear();
  document.body.innerHTML = "";
});

describe("onPageLoad", () => {
  it("runs the handler when the page has the root element", () => {
    document.body.innerHTML = '<div id="root"></div>';
    const event = new Event("turbo:load");
    document.dispatchEvent(event);
    expect(handler).toHaveBeenCalledWith(event);
  });

  it("does nothing on a page without the root element", () => {
    document.body.innerHTML = "<p>elsewhere</p>";
    document.dispatchEvent(new Event("turbo:load"));
    expect(handler).not.toHaveBeenCalled();
  });
});

describe("onEveryPageLoad", () => {
  it("runs the setup at once and again on every page load", () => {
    const setUp = vi.fn();
    onEveryPageLoad(setUp);
    expect(setUp).toHaveBeenCalledTimes(1);
    document.dispatchEvent(new Event("turbo:load"));
    document.dispatchEvent(new Event("turbo:load"));
    expect(setUp).toHaveBeenCalledTimes(3);
    document.removeEventListener("turbo:load", setUp);
  });
});

describe("oncePerElement", () => {
  it("binds an element once and a new element again", () => {
    const bind = vi.fn();
    const bindOnce = oncePerElement(bind);
    const first = document.createElement("button");
    const copy = first.cloneNode();
    bindOnce(first);
    bindOnce(first);
    bindOnce(copy);
    expect(bind.mock.calls).toEqual([[first], [copy]]);
  });

  it("skips a missing element", () => {
    const bind = vi.fn();
    oncePerElement(bind)(null);
    expect(bind).not.toHaveBeenCalled();
  });
});
