// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const picker = { clear: vi.fn(), destroy: vi.fn() };
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

async function mount() {
  document.body.innerHTML = `
    <div data-controller="date-picker">
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
