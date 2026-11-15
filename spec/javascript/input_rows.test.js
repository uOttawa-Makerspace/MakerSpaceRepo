// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";
import { addInputRow } from "../../app/javascript/src/input_rows.js";

beforeEach(() => {
  document.body.innerHTML = `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="add" class="btn btn-success"><i class="fa fa-plus"></i></button></div></div>`;
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

  it("leaves the add button the only element with its id", () => {
    addInputRow(add());
    addInputRow(add());
    expect(document.querySelectorAll('[id="add"]')).toHaveLength(1);
    expect(document.querySelectorAll(".wrap [id]")).toHaveLength(1);
  });
});
