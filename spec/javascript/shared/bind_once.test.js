// @vitest-environment happy-dom
import { describe, expect, it, vi } from "vitest";
import { bindOnce } from "../../../app/javascript/src/bind_once.js";

describe("bindOnce", () => {
  it("binds an element the first time only", () => {
    const el = document.createElement("div");
    const bind = vi.fn();
    bindOnce(el, bind);
    bindOnce(el, bind);
    expect(bind).toHaveBeenCalledTimes(1);
    expect(bind).toHaveBeenCalledWith(el);
  });

  it("binds a copy of the element again", () => {
    const el = document.createElement("div");
    const bind = vi.fn();
    bindOnce(el, bind);
    bindOnce(el.cloneNode(true), bind);
    expect(bind).toHaveBeenCalledTimes(2);
  });

  it("does nothing without an element", () => {
    const bind = vi.fn();
    bindOnce(null, bind);
    expect(bind).not.toHaveBeenCalled();
  });
});
