// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("bootstrap", () => ({ Modal: class {} }));

const { positionSaveButton } =
  await import("../../../app/javascript/src/calendar_helper.js");

const $ = (id) => document.getElementById(id);

const MODAL = `
  <div id="save_button_container"><input type="submit" value="Save Draft" id="save_button"></div>
  <div id="update_dropdown" style="display: none;">
    <div id="dropdown_save_button_container"></div>
  </div>`;

beforeEach(() => {
  document.body.innerHTML = MODAL;
});

const inMenu = () =>
  $("dropdown_save_button_container").contains($("save_button"));
const inMain = () => $("save_button_container").contains($("save_button"));

describe("positionSaveButton", () => {
  it("moves the button into the scope menu for a recurring edit", () => {
    positionSaveButton(true, true);
    expect(inMenu()).toBe(true);
    expect($("update_dropdown").style.display).toBe("block");
    expect($("save_button").value).toBe("Update");
  });

  it("keeps the button in the menu when it is already there", () => {
    $("dropdown_save_button_container").appendChild($("save_button"));
    const before = $("dropdown_save_button_container").firstChild;
    positionSaveButton(true, true);
    expect($("dropdown_save_button_container").firstChild).toBe(before);
    expect(inMenu()).toBe(true);
  });

  it("brings the button back out of the menu for a one-off edit", () => {
    $("dropdown_save_button_container").appendChild($("save_button"));
    $("update_dropdown").style.display = "block";
    positionSaveButton(false, true);
    expect(inMain()).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect($("save_button").value).toBe("Update");
  });

  it.each([
    [true, false],
    [false, false],
  ])(
    "keeps a new event's button in the main row as Save Draft (recurring %s)",
    (hasRecurrence, isEditing) => {
      $("save_button").value = "Update";
      positionSaveButton(hasRecurrence, isEditing);
      expect(inMain()).toBe(true);
      expect($("update_dropdown").style.display).toBe("none");
      expect($("save_button").value).toBe("Save Draft");
    },
  );

  it("does nothing without a save button", () => {
    $("save_button").remove();
    $("update_dropdown").style.display = "block";
    expect(() => positionSaveButton(true, true)).not.toThrow();
    expect($("update_dropdown").style.display).toBe("block");
  });

  it("leaves the button where it is when the menu container is missing", () => {
    $("dropdown_save_button_container").remove();
    positionSaveButton(true, true);
    expect(inMain()).toBe(true);
    expect($("update_dropdown").style.display).toBe("block");
    expect($("save_button").value).toBe("Update");
  });

  it("leaves the button where it is when the main container is missing", () => {
    $("dropdown_save_button_container").appendChild($("save_button"));
    $("save_button_container").remove();
    positionSaveButton(false, true);
    expect(inMenu()).toBe(true);
    expect($("save_button").value).toBe("Update");
  });

  it.each([
    [true, true, "Update"],
    [false, true, "Update"],
    [false, false, "Save Draft"],
  ])(
    "still sets the label without the menu (recurring %s, editing %s)",
    (hasRecurrence, isEditing, label) => {
      document.body.innerHTML =
        '<div id="save_button_container"><input type="submit" id="save_button"></div>';
      positionSaveButton(hasRecurrence, isEditing);
      expect($("save_button").value).toBe(label);
      expect(inMain()).toBe(true);
    },
  );
});
