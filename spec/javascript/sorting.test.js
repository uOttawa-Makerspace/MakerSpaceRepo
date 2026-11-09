// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";

await import("../../app/javascript/src/sorting.js");

const table = (rows, attr = "") => `
  <table class="t"><tbody>
    <tr><th>head</th></tr>
    ${rows.map((r) => `<tr><td ${attr.replace("$", r)}>${r}</td><td>x</td></tr>`).join("")}
  </tbody></table>`;

const column = () =>
  [...document.querySelectorAll(".t tr")]
    .slice(1)
    .map((tr) => tr.querySelector("td").textContent);

describe("findSession", () => {
  beforeEach(() => {
    document.body.innerHTML = `<input id="query" value="">
      <input id="other" value="">${table(["Alpha", "Beta", "alphabet"])}`;
  });

  const visible = () =>
    [...document.querySelectorAll(".t tr")]
      .slice(1)
      .filter((tr) => tr.style.display !== "none")
      .map((tr) => tr.querySelector("td").textContent);

  it("hides the rows that do not match, ignoring case and keeping the header", () => {
    document.getElementById("query").value = "alph";
    window.findSession("t");
    expect(visible()).toEqual(["Alpha", "alphabet"]);
    expect(document.querySelector(".t tr").style.display).not.toBe("none");
  });

  it("matches any cell in the row", () => {
    document.getElementById("query").value = "x";
    window.findSession("t");
    expect(visible()).toHaveLength(3);
  });

  it("shows every row again for an empty filter", () => {
    document.getElementById("query").value = "beta";
    window.findSession("t");
    document.getElementById("query").value = "";
    window.findSession("t");
    expect(visible()).toHaveLength(3);
  });

  it("reads the filter from another input when asked", () => {
    document.getElementById("other").value = "beta";
    window.findSession("t", "other");
    expect(visible()).toEqual(["Beta"]);
  });
});

describe("sortTable", () => {
  it("sorts text ascending then descending on each call", () => {
    document.body.innerHTML = table(["pear", "Apple", "mango"]);
    const first = (window.sortTable("t", 0), column());
    window.sortTable("t", 0);
    const second = column();
    // the direction alternates between calls; the two results are mirror images
    expect(second).toEqual([...first].reverse());
    expect(new Set([first.join(), second.join()])).toEqual(
      new Set(["Apple,mango,pear", "pear,mango,Apple"]),
    );
  });

  it("sorts by the sort key a cell provides", () => {
    document.body.innerHTML = `<table class="t"><tbody><tr><th></th></tr>
      <tr><td data-sort-as="b">one</td></tr>
      <tr><td data-sort-as="a">two</td></tr>
      <tr><td data-sort-as="c">three</td></tr></tbody></table>`;
    window.sortTable("t", 0);
    window.sortTable("t", 0);
    const keys = [...document.querySelectorAll(".t td")].map(
      (d) => d.textContent,
    );
    expect([keys.join(), [...keys].reverse().join()]).toContain(
      "two,one,three",
    );
  });

  it("sorts date columns by date, not by text", () => {
    document.body.innerHTML = table([
      "Nov 10, 2026",
      "Jan 5, 2026",
      "Dec 1, 2025",
    ]);
    window.sortTable("t", 0, true);
    const a = column();
    window.sortTable("t", 0, true);
    const b = column();
    expect([a.join(" | "), b.join(" | ")]).toContain(
      "Dec 1, 2025 | Jan 5, 2026 | Nov 10, 2026",
    );
    expect(b).toEqual([...a].reverse());
  });

  it("ignores a table that does not exist", () => {
    document.body.innerHTML = "";
    expect(() => window.sortTable("nope", 0)).not.toThrow();
  });
});

describe("selectAll", () => {
  it("ticks every box, then clears them on the next call", () => {
    document.body.innerHTML = `<table id="tbl"><tr><td>
      <input type="checkbox"><input type="checkbox"></td></tr></table>`;
    const boxes = () =>
      [...document.querySelectorAll("#tbl input")].map((b) => b.checked);

    expect(window.selectAll("tbl")).toBe(false);
    expect(boxes().every(Boolean)).toBe(true);
    window.selectAll("tbl");
    expect(boxes().some(Boolean)).toBe(false);
    window.selectAll("tbl");
    expect(boxes().every(Boolean)).toBe(true);
  });
});
