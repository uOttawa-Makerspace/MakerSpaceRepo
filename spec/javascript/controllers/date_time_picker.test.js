// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const picker = { destroy: vi.fn() };
const flatpickr = vi.fn(() => picker);
vi.mock("flatpickr", () => ({ default: flatpickr }));

const { default: DateTimePicker } =
  await import("../../../app/javascript/controllers/date_time_picker_controller.js");

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  document.documentElement.lang = "";
  vi.clearAllMocks();
});

async function mount() {
  document.body.innerHTML = `<input id="start" data-controller="date-time-picker">`;
  application = Application.start();
  application.register("date-time-picker", DateTimePicker);
  await settle();
}

describe("date-time-picker", () => {
  it("attaches a 24-hour date and time picker to its input", async () => {
    await mount();
    expect(flatpickr).toHaveBeenCalledWith(
      document.getElementById("start"),
      expect.objectContaining({
        enableTime: true,
        time_24hr: true,
        altInput: true,
        locale: "default",
      }),
    );
  });

  it("uses the page's language", async () => {
    document.documentElement.lang = "fr";
    await mount();
    expect(flatpickr.mock.calls[0][1].locale).not.toBe("default");
  });

  it("removes its picker when the input leaves the page", async () => {
    await mount();
    document.getElementById("start").remove();
    await settle();
    expect(picker.destroy).toHaveBeenCalledTimes(1);
  });
});
