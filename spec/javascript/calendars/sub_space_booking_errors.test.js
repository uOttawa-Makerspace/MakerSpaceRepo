// @vitest-environment happy-dom
// What the booking page tells the user when a request or the calendar feed fails.
import { beforeEach, describe, expect, it, vi } from "vitest";

let calendarOptions;
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(_element, options) {
      calendarOptions = options;
    }
    render() {}
    refetchEvents() {}
  },
}));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("tom-select", () => ({ default: class {} }));
vi.mock("flatpickr", () => ({ default: {} }));
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

const PAGE = `
<div id="booking_toast"
  data-failed-title="Booking failed" data-network="Server unreachable"
  data-no-reason="No reason given" data-feed="Bookings not loaded"
  data-unavailable-title="Booking unavailable" data-unavailable="Could not open it">
  <strong id="toast_title"></strong><div id="toast_text"></div>
</div>
<div id="booked-calendar"></div>
<div id="bookModal"></div>
<input id="book-start"><input id="book-end"><input id="book-recurring-end">
<input id="book-name"><input id="book-description"><input id="book-recurring" type="checkbox">
<input id="sub_space_booking_id" value="7">
<div id="end-date-validation"></div><div id="bookDeleteRecurringDropdown"></div>
<button id="bookCancel"></button><button id="bookClose"></button><button id="bookSave"></button>
<button id="bookUpdate"></button><button id="bookDelete"></button>
<button id="bookRecurringDeleteOne"></button><button id="bookRecurringDeleteRest"></button>`;

const toast = () => document.getElementById("toast_text").innerText;
const title = () => document.getElementById("toast_title").innerText;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function respond(response) {
  global.fetch = vi.fn(() =>
    response instanceof Error
      ? Promise.reject(response)
      : Promise.resolve(response),
  );
  document.getElementById("bookDelete").click();
  await settle();
}

const reply = (status, text) => ({ ok: status < 400, text: async () => text });

beforeEach(async () => {
  Element.prototype.flatpickr = () => ({
    selectedDates: [],
    input: { value: "" },
    altInput: document.createElement("input"),
    setDate() {},
  });
  window.scrollTo = vi.fn();
  global.confirm = vi.fn(() => true);
  document.body.innerHTML = PAGE;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/sub_space_booking.js");
  document.dispatchEvent(new Event("turbo:load"));
});

describe("a failed booking request", () => {
  it("shows the server's reason with its reference", async () => {
    await respond(
      reply(
        404,
        JSON.stringify({
          error: "That record could not be found.",
          reference: "ab12cd34",
        }),
      ),
    );
    expect(title()).toBe("Booking failed");
    expect(toast()).toBe("That record could not be found. [ab12cd34]");
  });

  it("says no reason came back when the answer is not JSON", async () => {
    await respond(reply(500, "<html>Internal Server Error</html>"));
    expect(toast()).toBe("No reason given");
  });

  it("says the server could not be reached when the request itself fails", async () => {
    await respond(new TypeError("Failed to fetch"));
    expect(title()).toBe("Booking failed");
    expect(toast()).toBe("Server unreachable");
  });

  it("keeps showing field errors for a 422 with errors", async () => {
    await respond(
      reply(
        422,
        JSON.stringify({
          errors: ["TimeSlot This time slot is already booked."],
        }),
      ),
    );
    expect(toast()).toBe("This time slot is already booked.");
  });
});

describe("a failed calendar feed", () => {
  const feedFailure = (error) => calendarOptions.eventSources[0].failure(error);

  it("shows the server's reason with its reference", async () => {
    await feedFailure({
      response: {
        json: async () => ({
          error: "Booking access required.",
          reference: "ff00ee11",
        }),
      },
    });
    expect(toast()).toBe("Booking access required. [ff00ee11]");
  });

  it("shows the translated fallback when the answer has no reason", async () => {
    await feedFailure({
      response: {
        json: async () => Promise.reject(new SyntaxError("not json")),
      },
    });
    expect(toast()).toBe("Bookings not loaded");
    await feedFailure(undefined);
    expect(toast()).toBe("Bookings not loaded");
  });
});
