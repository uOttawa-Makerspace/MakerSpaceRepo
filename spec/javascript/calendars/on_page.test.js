// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { onPageLoad } from "../../../app/javascript/src/on_page.js";

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
