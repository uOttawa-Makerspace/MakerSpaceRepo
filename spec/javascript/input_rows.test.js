// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";
import {
  addInputRow,
  bindInputRows,
} from "../../app/javascript/src/input_rows.js";

beforeEach(() => {
  document.body.innerHTML = `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="add" class="btn btn-success" aria-label="Add file" data-remove-label="Remove"><i class="fa fa-plus"></i></button></div></div>`;
});

const add = () => document.getElementById("add");

describe("addInputRow", () => {
  it("adds a row with an empty input and a remove button after the rows", () => {
    const remove = addInputRow(add());
    const rows = document.querySelectorAll(".wrap > .input-group");
    expect(rows).toHaveLength(2);
    expect(rows[1].children[1]).toBe(remove);
    expect(rows[1].querySelector("input").value).toBe("");
    expect(remove.className).toBe("btn btn-danger");
    expect(remove.children[0].className).toBe("fa fa-trash");
  });

  it("labels the remove button as one, from the add button's remove label", () => {
    const remove = addInputRow(add());
    expect(remove.getAttribute("aria-label")).toBe("Remove");
    expect(add().getAttribute("aria-label")).toBe("Add file");
  });

  it("sets no remove label when the add button has none", () => {
    add().removeAttribute("data-remove-label");
    const remove = addInputRow(add());
    expect(remove.getAttribute("aria-label")).toBe("Add file");
  });

  it("leaves the add button the only element with its id", () => {
    addInputRow(add());
    addInputRow(add());
    expect(document.querySelectorAll('[id="add"]')).toHaveLength(1);
    expect(document.querySelectorAll(".wrap [id]")).toHaveLength(1);
  });
});

describe("bindInputRows", () => {
  const rows = () => document.querySelectorAll(".wrap > .input-group");

  it("adds a row for each click on the add button", () => {
    bindInputRows(add());
    add().click();
    add().click();
    expect(rows()).toHaveLength(3);
  });

  it("binds the add button once when bound again", () => {
    bindInputRows(add());
    bindInputRows(add());
    add().click();
    expect(rows()).toHaveLength(2);
  });

  it("removes a row with its remove button, also by its icon", () => {
    bindInputRows(add());
    add().click();
    add().click();
    rows()[1].querySelector(".btn-danger").click();
    expect(rows()).toHaveLength(2);
    rows()[1].querySelector(".btn-danger i").click();
    expect(rows()).toHaveLength(1);
  });

  it("removes rows that were on the page before it was bound", () => {
    document
      .querySelector(".wrap")
      .insertAdjacentHTML(
        "beforeend",
        '<div class="input-group"><input type="file"><button class="btn btn-danger"><i></i></button></div>',
      );
    bindInputRows(add());
    rows()[1].querySelector(".btn-danger").click();
    expect(rows()).toHaveLength(1);
  });

  it("does not remove the first row with the add button", () => {
    bindInputRows(add());
    add().click();
    expect(rows()).toHaveLength(2);
    add().querySelector("i").click();
    expect(rows()).toHaveLength(3);
  });

  it("skips a missing add button", () => {
    expect(() => bindInputRows(null)).not.toThrow();
  });
});
