// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const picker = { clear: vi.fn(), destroy: vi.fn(), altInput: null };
const flatpickr = vi.fn(() => picker);
vi.mock("flatpickr", () => ({ default: flatpickr }));

const { default: DatePicker } =
  await import("../../../app/javascript/controllers/date_picker_controller.js");

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  vi.clearAllMocks();
});

async function mount({ label = false } = {}) {
  picker.altInput = document.createElement("input");
  document.body.innerHTML = `
    <div data-controller="date-picker">
      ${label ? '<label id="lbl" for="end">End</label>' : ""}
      <input id="end" data-date-picker-target="input">
      <button id="clear" data-action="date-picker#clear"></button>
    </div>`;
  application = Application.start();
  application.register("date-picker", DatePicker);
  await settle();
}

describe("date-picker", () => {
  it("attaches a future-only calendar to its own input", async () => {
    await mount();
    expect(flatpickr).toHaveBeenCalledWith(
      document.getElementById("end"),
      expect.objectContaining({ minDate: "today", dateFormat: "Y-m-d" }),
    );
  });

  it("points the label at the visible calendar input", async () => {
    await mount({ label: true });
    expect(picker.altInput.id).toBe("end_display");
    expect(document.getElementById("lbl").getAttribute("for")).toBe(
      "end_display",
    );
  });

  it("labels the new visible field after a disconnect and reconnect", async () => {
    await mount({ label: true });
    const root = document.querySelector("[data-controller]");
    const parent = root.parentNode;
    parent.removeChild(root);
    await settle();
    expect(root.querySelector("label").getAttribute("for")).toBe("end");
    picker.altInput = document.createElement("input");
    parent.appendChild(root);
    await settle();
    expect(picker.altInput.id).toBe("end_display");
    expect(root.querySelector("label").getAttribute("for")).toBe("end_display");
  });

  it("leaves the inputs alone when there is no label", async () => {
    await mount();
    expect(picker.altInput.id).toBe("");
  });

  it("clears the date from the clear button", async () => {
    await mount();
    document.getElementById("clear").click();
    expect(picker.clear).toHaveBeenCalled();
  });

  it("destroys the calendar when the element goes away", async () => {
    await mount();
    document.body.innerHTML = "";
    await settle();
    expect(picker.destroy).toHaveBeenCalled();
  });
});
