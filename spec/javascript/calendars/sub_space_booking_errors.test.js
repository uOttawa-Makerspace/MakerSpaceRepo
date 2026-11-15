// @vitest-environment happy-dom
// What the booking page tells the user when a request or the calendar feed fails.
import { beforeEach, describe, expect, it, vi } from "vitest";

import { textsAttribute } from "./calendar_texts_fixture.js";
import {
  settle,
  startBookingControllers,
  withControllers,
} from "./booking_page_fixture.js";

let calendarOptions;
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(_element, options) {
      calendarOptions = options;
    }
    render() {}
    destroy() {}
    refetchEvents() {}
  },
}));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("flatpickr", () => ({ default: {} }));
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

const PAGE = `
<div id="booking_toast"
  data-failed-title="Booking failed"
  data-updated-title="Booking updated" data-updated="Saved."
  data-feed="Bookings not loaded"
  data-unavailable-title="Booking unavailable" data-unavailable="Could not open it">
  <div class="toast-header"><strong id="toast_title"></strong></div><div id="toast_text"></div>
</div>
<div id="booked-calendar" ${textsAttribute()}></div>
<div id="bookModal">
<input id="book-start"><input id="book-end"><input id="book-recurring-end">
<input id="book-name"><input id="book-description"><input id="book-recurring" type="checkbox">
<input id="sub_space_booking_id" value="7">
<div id="end-date-validation"></div><div id="bookDeleteRecurringDropdown"></div>
<button id="bookCancel"></button><button id="bookClose"></button><button id="bookSave"></button>
<button id="bookUpdate"></button><button id="bookDelete"></button>
<div id="subspace"></div><div id="subspace_header"></div><h5 id="bookingModalLabel"></h5><label id="book-recurring-label"></label>
<button id="bookRecurringDeleteOne"></button><button id="bookRecurringDeleteRest"></button>
</div>`;

const toast = () => document.getElementById("toast_text").innerText;
const title = () => document.getElementById("toast_title").innerText;

async function respond(response) {
  global.fetch = vi.fn(() =>
    response instanceof Error
      ? Promise.reject(response)
      : Promise.resolve(response),
  );
  document
    .getElementById("bookDelete")
    .dispatchEvent(new CustomEvent("confirmation:confirmed"));
  await settle();
}

const reply = (status, text) => ({ ok: status < 400, text: async () => text });

Element.prototype.flatpickr = () => ({
  selectedDates: [],
  input: { value: "" },
  altInput: document.createElement("input"),
  destroy() {},
  setDate() {},
});
await startBookingControllers();

beforeEach(async () => {
  window.scrollTo = vi.fn();
  global.confirm = vi.fn(() => true);
  document.body.innerHTML = withControllers(PAGE);
  document.documentElement.dataset.requestNetwork = "Server unreachable";
  document.documentElement.dataset.requestFailed = "No reason given";
  document.dispatchEvent(new Event("turbo:load"));
  await settle();
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

  it("adds the request id to the generic text when the answer carries one", async () => {
    await respond({
      ok: false,
      headers: new Headers({ "X-Request-Id": "abcdef0123456789" }),
      text: async () => "<html></html>",
    });
    expect(toast()).toBe("No reason given [abcdef01]");
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

describe("a saved booking update", () => {
  const save = async (response) => {
    global.fetch = vi.fn(() => Promise.resolve(response));
    document.getElementById("bookUpdate").click();
    await settle();
  };
  const toastEl = () => document.getElementById("booking_toast");

  it("shows a green success message without reloading", async () => {
    await save(reply(200, JSON.stringify({ status: "ok" })));
    expect(title()).toBe("Booking updated");
    expect(toast()).toBe("Saved.");
    expect(toastEl().classList.contains("text-bg-success")).toBe(true);
    expect(toastEl().classList.contains("text-bg-danger")).toBe(false);
  });

  it("returns to the red style for the next failure", async () => {
    await save(reply(200, JSON.stringify({ status: "ok" })));
    await save(reply(500, ""));
    expect(title()).toBe("Booking failed");
    expect(toastEl().classList.contains("text-bg-danger")).toBe(true);
    expect(toastEl().classList.contains("text-bg-success")).toBe(false);
  });

  it.each(["TimeSlot Slot taken.", "DurationHour Too long."])(
    "a field error (%s) after a success shows the red style only",
    async (error) => {
      await save(reply(200, JSON.stringify({ status: "ok" })));
      await save(reply(422, JSON.stringify({ errors: [error] })));
      expect(title()).toBe("Booking failed");
      expect(toastEl().classList.contains("text-bg-danger")).toBe(true);
      expect(toastEl().classList.contains("text-bg-success")).toBe(false);
    },
  );

  it("shows no success message after a delete", async () => {
    await respond(reply(200, JSON.stringify({ status: "ok" })));
    expect(toast()).toBe("");
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

describe("a failed booking lookup", () => {
  const open = async (response) => {
    global.fetch = vi.fn(() =>
      response instanceof Error
        ? Promise.reject(response)
        : Promise.resolve(response),
    );
    calendarOptions.eventClick({
      event: { id: "b_7", extendedProps: { viewable: true } },
    });
    await settle();
  };

  it("shows the translated network text, never the browser's message", async () => {
    await open(new TypeError("Failed to fetch"));
    expect(title()).toBe("Booking unavailable");
    expect(toast()).toBe("Server unreachable");
  });

  it("shows the server's reason with its reference", async () => {
    await open({
      ok: false,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () =>
        JSON.stringify({ error: "Not allowed.", reference: "aa11bb22" }),
    });
    expect(toast()).toBe("Not allowed. [aa11bb22]");
  });

  it("falls back to the translated text for an answer that is not JSON", async () => {
    await open({
      ok: true,
      headers: new Headers({ "content-type": "text/html" }),
      text: async () => "<html></html>",
    });
    expect(toast()).toBe("Could not open it");
  });

  it("shows the translated text for an OK JSON answer with no body", async () => {
    await open({
      ok: true,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => "",
    });
    expect(title()).toBe("Booking unavailable");
    expect(toast()).toBe("Could not open it");
  });

  it("shows the translated text when the booking cannot be filled into the form", async () => {
    await open({
      ok: true,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => JSON.stringify({ name: "Lab" }),
    });
    expect(title()).toBe("Booking unavailable");
    expect(toast()).toBe("Could not open it");
  });
});
