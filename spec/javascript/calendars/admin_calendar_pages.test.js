// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("flatpickr", () => ({}));

// the page script uses the global the flatpickr bundle defines
let destroy;
let flatpickr;
beforeEach(() => {
  destroy = vi.fn();
  flatpickr = vi.fn(() => ({ destroy }));
  vi.stubGlobal("flatpickr", flatpickr);
});
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
    const toasts = () => document.querySelectorAll(".toast");

    const pickColor = async (answer) => {
      document.body.innerHTML =
        '<button id="addEventButton"></button><button id="refresh_calendar"></button>' +
        '<section data-color-not-saved="Not saved."></section>' +
        '<input class="staff_color_select" data-user="7" value="#ff0000">';
      document.dispatchEvent(new Event("turbo:load"));
      const fetchMock = vi.fn(() => answer);
      vi.stubGlobal("fetch", fetchMock);
      document
        .querySelector(".staff_color_select")
        .dispatchEvent(new Event("change"));
      await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled());
      await new Promise((resolve) => setTimeout(resolve));
      return fetchMock;
    };

    it("posts the colour and stays quiet when it is saved", async () => {
      const fetchMock = await pickColor(Promise.resolve({ ok: true }));

      expect(fetchMock).toHaveBeenCalledWith(
        "/admin/calendar/update_color",
        expect.objectContaining({ method: "POST" }),
      );
      expect(toasts()).toHaveLength(0);
    });

    it("toasts the server's reason when it refuses the colour", async () => {
      await pickColor(
        Promise.resolve({
          ok: false,
          json: () => Promise.resolve({ error: "<b>Why</b>" }),
        }),
      );

      expect(toasts()).toHaveLength(1);
      expect(toasts()[0].textContent).toContain("Not saved. <b>Why</b>");
    });

    it("toasts the page text when the refusal has no readable reason", async () => {
      await pickColor(
        Promise.resolve({ ok: false, json: () => Promise.reject(new Error()) }),
      );

      expect(toasts()[0].textContent).toContain("Not saved.");
    });

    it("toasts the page text when the request fails", async () => {
      await pickColor(Promise.reject(new Error("offline")));

      expect(toasts()[0].textContent).toContain("Not saved.");
    });
  });

  it("saves a staff colour when it is changed", async () => {
    document.body.innerHTML = `<button id="addEventButton"></button>
      <button id="refresh_calendar"></button>
      <section data-color-not-saved="Not saved."></section>
      <input class="staff_color_select" data-user="9" value="#00ff00">`;
    const fetchMock = vi.fn(() => Promise.resolve({ ok: true }));
    vi.stubGlobal("fetch", fetchMock);
    document.dispatchEvent(new Event("turbo:load"));

    document
      .querySelector(".staff_color_select")
      .dispatchEvent(new Event("change", { bubbles: true }));

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/admin/calendar/update_color");
    expect(init.method).toBe("POST");
    expect(JSON.parse(init.body)).toEqual({
      user_id: "9",
      color: "#00ff00",
      format: "json",
    });
  });

  it("reloads the page in place from the refresh button", () => {
    document.body.innerHTML =
      '<button id="addEventButton"></button><button id="refresh_calendar"></button>';
    const visit = vi.fn();
    vi.stubGlobal("Turbo", { visit });
    document.dispatchEvent(new Event("turbo:load"));

    document.getElementById("refresh_calendar").click();

    expect(visit).toHaveBeenCalledWith(window.location, { action: "replace" });
  });

  it("keeps the copy dialog date pickers working when it closes", () => {
    document.body.innerHTML = `<button id="addEventButton"></button>
      <button id="refresh_calendar"></button><div id="copyEventsModal"></div>`;
    destroy.mockClear();
    const errors = [];
    const onError = (e) => errors.push(e.error ?? e.message);
    window.addEventListener("error", onError);
    document.dispatchEvent(new Event("turbo:load"));

    document
      .getElementById("copyEventsModal")
      .dispatchEvent(new Event("hide.bs.modal"));
    window.removeEventListener("error", onError);

    expect(errors).toEqual([]);
    expect(destroy).not.toHaveBeenCalled();
  });
});
