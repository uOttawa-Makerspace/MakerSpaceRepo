import { describe, expect, it, vi } from "vitest";

// The module also drives a Bootstrap modal; the functions under test never touch it.
vi.mock("bootstrap", () => ({ Modal: class {} }));

const { toLocalDatetimeString, toLocalDateString, parseLocalDatetimeString } =
  await import("../../app/javascript/src/calendar_helper.js");

describe("toLocalDatetimeString", () => {
  it("formats local date and time as YYYY-MM-DDTHH:MM", () => {
    expect(toLocalDatetimeString(new Date(2026, 10, 5, 14, 30))).toBe(
      "2026-11-05T14:30",
    );
  });

  it("zero-pads single-digit month, day, hour and minute", () => {
    expect(toLocalDatetimeString(new Date(2026, 0, 2, 3, 4))).toBe(
      "2026-01-02T03:04",
    );
  });

  it("drops seconds", () => {
    expect(toLocalDatetimeString(new Date(2026, 5, 15, 23, 59, 59))).toBe(
      "2026-06-15T23:59",
    );
  });

  it("returns null for an empty value", () => {
    expect(toLocalDatetimeString(null)).toBeNull();
    expect(toLocalDatetimeString(undefined)).toBeNull();
  });
});

describe("toLocalDateString", () => {
  it("formats the local date as YYYY-MM-DD with zero padding", () => {
    expect(toLocalDateString(new Date(2026, 0, 9, 23, 59))).toBe("2026-01-09");
    expect(toLocalDateString(new Date(2026, 11, 31, 0, 0))).toBe("2026-12-31");
  });

  it("returns null for an empty value", () => {
    expect(toLocalDateString(null)).toBeNull();
  });
});

describe("parseLocalDatetimeString", () => {
  it("reads YYYY-MM-DDTHH:MM as local time", () => {
    const parsed = parseLocalDatetimeString("2026-11-05T14:30");
    expect(parsed.getFullYear()).toBe(2026);
    expect(parsed.getMonth()).toBe(10);
    expect(parsed.getDate()).toBe(5);
    expect(parsed.getHours()).toBe(14);
    expect(parsed.getMinutes()).toBe(30);
  });

  it("round-trips through toLocalDatetimeString", () => {
    expect(
      toLocalDatetimeString(parseLocalDatetimeString("2026-03-08T02:15")),
    ).toBe("2026-03-08T02:15");
  });

  it("returns the current time for an empty value", () => {
    const before = Date.now();
    const parsed = parseLocalDatetimeString("");
    expect(parsed.getTime()).toBeGreaterThanOrEqual(before);
    expect(parsed.getTime()).toBeLessThanOrEqual(Date.now());
  });
});
