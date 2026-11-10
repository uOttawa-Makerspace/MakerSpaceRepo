import { describe, expect, it, vi } from "vitest";

// A spy made in one example must be gone in the next, so a "not called"
// assertion never depends on which examples ran before it.
describe("spies between examples", () => {
  it("records a call on a console spy", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    console.warn("noise");
    expect(warn).toHaveBeenCalledTimes(1);
  });

  it("starts the next example with the real console method", () => {
    expect(vi.isMockFunction(console.warn)).toBe(false);
  });
});
