// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

// The entry file wires third-party widgets at import time; the functions under
// test never touch them.
vi.mock("bootstrap", () => ({ Tooltip: class {} }));
vi.mock("tom-select", () => ({ default: class {} }));
vi.mock("datatables.net-bs5", () => ({ default: class {} }));
vi.mock("datatables.net-select-bs5", () => ({}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: () => ({}),
}));

const { findContiguous, handleLinkInput, validateRange } =
  await import("../../../app/javascript/entrypoints/lockers.js");

describe("findContiguous", () => {
  it("returns no groups for an empty set", () => {
    expect(findContiguous(new Set())).toEqual([]);
  });

  it("returns a single one-element group for one number", () => {
    expect(findContiguous(new Set(["7"]))).toEqual([[7, 7]]);
  });

  it("joins consecutive numbers into one group", () => {
    expect(findContiguous(["1", "2", "3"])).toEqual([[1, 3]]);
  });

  it("splits at gaps and sorts numerically, not as text", () => {
    expect(findContiguous(["10", "2", "3", "9", "11"])).toEqual([
      [2, 3],
      [9, 11],
    ]);
  });

  it("makes NaN groups out of non-numeric specifiers", () => {
    const groups = findContiguous(["A1"]);
    expect(groups).toHaveLength(1);
    expect(Number.isNaN(groups[0][0])).toBe(true);
  });
});

describe("handleLinkInput", () => {
  beforeEach(() => {
    document.body.innerHTML = `<input id="link"><input id="value" value="old">`;
  });

  const paste = (text) => {
    const link = document.getElementById("link");
    link.value = text;
    handleLinkInput.call(link);
    return document.getElementById("value").value;
  };

  it("copies the product id from a product url", () => {
    expect(
      paste("https://admin.shopify.com/store/x/products/10478024917048"),
    ).toBe("10478024917048");
  });

  it("matches the products segment case-insensitively", () => {
    expect(paste("https://x.test/Products/42?variant=9")).toBe("42");
  });

  it("keeps the old value when the text has no product id", () => {
    expect(paste("https://x.test/collections/5")).toBe("old");
  });

  it("keeps the old value when the field is cleared", () => {
    expect(paste("")).toBe("old");
  });

  it("does nothing when there is no value field", () => {
    document.getElementById("value").remove();
    const link = document.getElementById("link");
    link.value = "https://x.test/products/1";
    expect(() => handleLinkInput.call(link)).not.toThrow();
  });
});

describe("validateRange", () => {
  const fixture = (existing, start, end) => {
    document.body.innerHTML = `
      <div id="newRangeLockerModal" data-locker-specifiers='${JSON.stringify(existing)}'>
        <input id="newLockerRangeStart" value="${start}">
        <input id="newLockerRangeEnd" value="${end}">
        <div id="newRangeLockersAlreadyPresent"><ul><li>stale</li></ul></div>
        <div id="newRangeLockersPossible"><ul><li>stale</li></ul></div>
      </div>`;
  };
  const items = (id) =>
    [...document.querySelectorAll(`#${id} li`)].map((li) => li.textContent);
  const hidden = (id) => document.getElementById(id).hidden;

  it("lists existing and creatable lockers as collapsed ranges", () => {
    fixture(["3", "4", "5", "9"], 1, 10);
    validateRange();
    expect(items("newRangeLockersAlreadyPresent")).toEqual([
      "Range from 3 to 5",
      "9",
    ]);
    expect(items("newRangeLockersPossible")).toEqual([
      "Range from 1 to 2",
      "Range from 6 to 8",
      "10",
    ]);
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(false);
    expect(hidden("newRangeLockersPossible")).toBe(false);
  });

  it("hides the already-there list when nothing overlaps", () => {
    fixture(["50"], 1, 3);
    validateRange();
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(true);
    expect(items("newRangeLockersPossible")).toEqual(["Range from 1 to 3"]);
  });

  it("hides the creatable list when every locker exists", () => {
    fixture(["1", "2"], 1, 2);
    validateRange();
    expect(hidden("newRangeLockersPossible")).toBe(true);
    expect(items("newRangeLockersAlreadyPresent")).toEqual([
      "Range from 1 to 2",
    ]);
  });

  it("leaves the lists untouched while the range is incomplete", () => {
    fixture([], "", 5);
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["stale"]);
  });

  it("leaves the lists untouched when start is above end", () => {
    fixture([], 9, 5);
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["stale"]);
  });

  it("treats a one-number range as a single creatable locker", () => {
    fixture([], 4, 4);
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["4"]);
  });

  it("does nothing without the modal", () => {
    document.body.innerHTML = "";
    expect(() => validateRange()).not.toThrow();
  });

  it("leaves the lists untouched when the modal has no end field", () => {
    fixture([], 1, 3);
    document.getElementById("newLockerRangeEnd").remove();
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["stale"]);
    expect(hidden("newRangeLockersPossible")).toBe(false);
  });

  it("leaves the lists untouched when the modal has no start field", () => {
    fixture([], 1, 3);
    document.getElementById("newLockerRangeStart").remove();
    validateRange();
    expect(items("newRangeLockersAlreadyPresent")).toEqual(["stale"]);
  });

  it("reads the leading number of each field", () => {
    fixture(["2"], "1abc", "3 lockers");
    validateRange();
    expect(items("newRangeLockersAlreadyPresent")).toEqual(["2"]);
    expect(items("newRangeLockersPossible")).toEqual(["1", "3"]);
  });

  it("compares names as text, as the server does: 01 and A1 are not 1", () => {
    fixture(["A1", "01", "2"], 1, 2);
    validateRange();
    expect(items("newRangeLockersAlreadyPresent")).toEqual(["2"]);
    expect(items("newRangeLockersPossible")).toEqual(["1"]);
  });

  it("empties a list it hides", () => {
    fixture(["50"], 1, 3);
    validateRange();
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(true);
    expect(items("newRangeLockersAlreadyPresent")).toEqual([]);
  });

  it("shows a list again once it has items", () => {
    fixture(["2"], 1, 1);
    validateRange();
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(true);
    document.getElementById("newLockerRangeEnd").value = "3";
    validateRange();
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(false);
    expect(items("newRangeLockersAlreadyPresent")).toEqual(["2"]);
  });

  it("fills the other list when one list is missing from the page", () => {
    fixture(["2"], 1, 3);
    document.getElementById("newRangeLockersAlreadyPresent").remove();
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["1", "3"]);
  });

  it("fills the existing list when the creatable list is missing", () => {
    fixture(["2"], 1, 3);
    document.getElementById("newRangeLockersPossible").remove();
    validateRange();
    expect(items("newRangeLockersAlreadyPresent")).toEqual(["2"]);
  });

  it("reads the lists and the existing lockers from the modal only", () => {
    document.body.innerHTML = `
      <div id="newRangeLockerModal" data-locker-specifiers='["2"]'>
        <input id="newLockerRangeStart" value="1">
        <input id="newLockerRangeEnd" value="4">
        <div id="newRangeLockersAlreadyPresent"><ul></ul></div>
        <div id="newRangeLockersPossible"><ul></ul></div>
      </div>
      <div id="newRangeLockersAlreadyPresent"><ul><li>outside</li></ul></div>
      <table><tr data-locker-specifier="3"></tr></table>`;
    validateRange();
    const modal = document.getElementById("newRangeLockerModal");
    const inModal = (id) =>
      [...modal.querySelectorAll(`#${id} li`)].map((li) => li.textContent);
    expect(inModal("newRangeLockersAlreadyPresent")).toEqual(["2"]);
    expect(inModal("newRangeLockersPossible")).toEqual([
      "1",
      "Range from 3 to 4",
    ]);
    expect(
      document.querySelector("body > #newRangeLockersAlreadyPresent")
        .textContent,
    ).toBe("outside");
  });

  it("treats every locker as new when the modal lists no existing lockers", () => {
    document.body.innerHTML = `
      <div id="newRangeLockerModal">
        <input id="newLockerRangeStart" value="1">
        <input id="newLockerRangeEnd" value="2">
        <div id="newRangeLockersAlreadyPresent"><ul><li>stale</li></ul></div>
        <div id="newRangeLockersPossible"><ul></ul></div>
      </div>`;
    validateRange();
    expect(items("newRangeLockersPossible")).toEqual(["Range from 1 to 2"]);
    expect(hidden("newRangeLockersAlreadyPresent")).toBe(true);
    expect(items("newRangeLockersAlreadyPresent")).toEqual([]);
  });
});
