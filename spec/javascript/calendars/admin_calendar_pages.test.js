// @vitest-environment happy-dom
import { describe, expect, it, vi } from "vitest";

vi.mock("flatpickr", () => ({}));

// the page script uses the global the flatpickr bundle defines
const flatpickr = vi.fn(() => ({ flatpickr: () => ({ destroy() {} }) }));
vi.stubGlobal("flatpickr", flatpickr);
vi.mock("../../../app/javascript/src/fullcalendar_setup_admin", () => ({}));
vi.mock("../../../app/javascript/src/manage_calendar_events", () => ({}));
vi.mock("../../../app/javascript/src/calendar_helper", () => ({
  addEventClick: vi.fn(),
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

await import("../../../app/javascript/entrypoints/calendar.js");

describe("admin calendar entrypoint", () => {
  it("does nothing on a page without the calendar", () => {
    document.body.innerHTML = "<p>another page</p>";
    const errors = [];
    window.addEventListener("error", (e) => errors.push(e.error));
    document.dispatchEvent(new Event("turbo:load"));

    expect(errors).toEqual([]);
    expect(flatpickr).not.toHaveBeenCalled();
  });

  it("wires the add button on the calendar page", () => {
    document.body.innerHTML =
      '<button id="addEventButton"></button><button id="refresh_calendar"></button>';
    document.dispatchEvent(new Event("turbo:load"));

    expect(flatpickr).toHaveBeenCalledWith("#source_range", expect.anything());
  });

  describe("staff colour picker", () => {
    const pickColor = async (response) => {
      document.body.innerHTML =
        '<button id="addEventButton"></button><button id="refresh_calendar"></button>' +
        '<input class="staff_color_select" data-user="7" value="#ff0000">';
      document.dispatchEvent(new Event("turbo:load"));
      const fetchMock = vi.fn(() => Promise.resolve(response));
      vi.stubGlobal("fetch", fetchMock);
      const error = vi.spyOn(console, "error").mockImplementation(() => {});
      document
        .querySelector(".staff_color_select")
        .dispatchEvent(new Event("change"));
      await Promise.resolve();
      await Promise.resolve();
      return { fetchMock, error };
    };

    it("posts the colour and stays quiet when it is saved", async () => {
      const { fetchMock, error } = await pickColor({ ok: true });

      expect(fetchMock).toHaveBeenCalledWith(
        "/admin/calendar/update_color",
        expect.objectContaining({ method: "POST" }),
      );
      expect(error).not.toHaveBeenCalled();
      error.mockRestore();
    });

    it("reports an error when the server refuses the colour", async () => {
      const { error } = await pickColor({ ok: false, status: 422 });

      expect(error).toHaveBeenCalledWith(
        "The staff colour could not be saved.",
      );
      error.mockRestore();
    });
  });
});
