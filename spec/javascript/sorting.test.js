// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

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

// Each example loads the script afresh, so the shared sort direction starts
// at ascending.
describe("sortTable (fresh page)", () => {
  beforeEach(async () => {
    vi.resetModules();
    await import("../../app/javascript/src/sorting.js");
  });

  const grid = (
    cells,
  ) => `<table class="t"><thead><tr><th>a</th><th>b</th></tr></thead><tbody>
    ${cells.map((c) => `<tr>${c.map((v) => `<td>${v}</td>`).join("")}</tr>`).join("")}
    </tbody></table>`;
  const col = (n) =>
    [...document.querySelectorAll(".t tbody tr")].map(
      (tr) => tr.querySelectorAll("td")[n].textContent,
    );

  it("sorts text ascending on the first call and descending on the second", () => {
    document.body.innerHTML = table(["pear", "Apple", "mango"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["Apple", "mango", "pear"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["pear", "mango", "Apple"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["Apple", "mango", "pear"]);
  });

  it("compares text without regard to case", () => {
    document.body.innerHTML = table(["b", "C", "a"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["a", "b", "C"]);
  });

  it("keeps rows with equal keys in their original order", () => {
    document.body.innerHTML = grid([
      ["x", "1"],
      ["X", "2"],
      ["a", "3"],
      ["x", "4"],
    ]);
    window.sortTable("t", 0);
    expect(col(1)).toEqual(["3", "1", "2", "4"]);
  });

  it("sorts by the column asked for and moves whole rows", () => {
    document.body.innerHTML = grid([
      ["one", "c"],
      ["two", "a"],
      ["three", "b"],
    ]);
    window.sortTable("t", 1);
    expect(col(0)).toEqual(["two", "three", "one"]);
    expect(col(1)).toEqual(["a", "b", "c"]);
  });

  it("compares numbers as text", () => {
    document.body.innerHTML = table(["9", "10", "100", "2"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["10", "100", "2", "9"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["9", "2", "100", "10"]);
  });

  it("puts empty cells first going up and last going down", () => {
    document.body.innerHTML = table(["b", "", "a"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["", "a", "b"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["b", "a", ""]);
  });

  it("uses the cell text when the sort key is empty", () => {
    document.body.innerHTML = `<table class="t"><tbody><tr><th></th></tr>
      <tr><td data-sort-as="">b</td></tr>
      <tr><td data-sort-as="c">a</td></tr>
      <tr><td>a</td></tr></tbody></table>`;
    window.sortTable("t", 0);
    expect(column()).toEqual(["a", "b", "a"]);
  });

  it("sorts date columns oldest first, then newest first", () => {
    document.body.innerHTML = table([
      "Nov 10, 2026",
      "Jan 5, 2026",
      "Dec 1, 2025",
    ]);
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["Dec 1, 2025", "Jan 5, 2026", "Nov 10, 2026"]);
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["Nov 10, 2026", "Jan 5, 2026", "Dec 1, 2025"]);
  });

  it("sorts a date column by each cell's sort key", () => {
    document.body.innerHTML = `<table class="t"><tbody><tr><th></th></tr>
      <tr><td data-sort-as="2026-03-01">Mar 1 - Mar 4</td></tr>
      <tr><td data-sort-as="2026-01-01">Jan 1 - Feb 9</td></tr></tbody></table>`;
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["Jan 1 - Feb 9", "Mar 1 - Mar 4"]);
  });

  it("never picks a cell that is not a date, so it drifts to the end", () => {
    document.body.innerHTML = table(["Jan 5, 2026", "soon", "Dec 1, 2025"]);
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["Dec 1, 2025", "Jan 5, 2026", "soon"]);
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["Jan 5, 2026", "Dec 1, 2025", "soon"]);
  });

  it("does not sort a date column as text", () => {
    document.body.innerHTML = table(["b", "a", "c"]);
    window.sortTable("t", 0, true);
    expect(column()).toEqual(["b", "a", "c"]);
  });

  it("shares one direction across every table and column on the page", () => {
    document.body.innerHTML =
      table(["b", "a"]) +
      `<table class="u"><tbody><tr><th></th></tr><tr><td>a</td></tr><tr><td>b</td></tr></tbody></table>`;
    window.sortTable("t", 0);
    expect(column()).toEqual(["a", "b"]);
    window.sortTable("u", 0);
    expect(
      [...document.querySelectorAll(".u td")].map((d) => d.textContent),
    ).toEqual(["b", "a"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["a", "b"]);
  });

  it("sorts only the first table with the class", () => {
    document.body.innerHTML = table(["b", "a"]) + table(["d", "c"]);
    window.sortTable("t", 0);
    const tables = [...document.querySelectorAll("table.t")].map((t) =>
      [...t.querySelectorAll("td:first-child")].map((d) => d.textContent),
    );
    expect(tables).toEqual([
      ["a", "b"],
      ["d", "c"],
    ]);
  });

  it("flips the direction even when there is nothing to sort", () => {
    document.body.innerHTML = table(["only"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["only"]);
    document.body.innerHTML = table(["a", "b"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["b", "a"]);
  });

  it("keeps the direction when the table is missing", () => {
    document.body.innerHTML = "";
    window.sortTable("t", 0);
    document.body.innerHTML = table(["b", "a"]);
    window.sortTable("t", 0);
    expect(column()).toEqual(["a", "b"]);
  });

  it("sorts a row with no cell in that column as an empty cell", () => {
    document.body.innerHTML = grid([["a", "2"], ["b"], ["c", "1"]]);
    window.sortTable("t", 1);
    expect(col(0)).toEqual(["b", "c", "a"]);
    window.sortTable("t", 1);
    expect(col(0)).toEqual(["a", "c", "b"]);
  });
});
