// @vitest-environment happy-dom
// The booking page's save and delete requests as sent, what each kind of answer does to the
// page, and what every Turbo visit sets up again.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { textsAttribute } from "./calendar_texts_fixture.js";
import {
  settle,
  startBookingControllers,
  withControllers,
} from "./booking_page_fixture.js";

const calendars = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = options;
      this.refetched = 0;
      calendars.push(this);
    }
    refetchEvents() {
      this.refetched++;
    }
    render() {}
    destroy() {}
  },
}));
vi.mock("@fullcalendar/interaction", () => ({
  default: { name: "interaction" },
}));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: { name: "list" } }));
vi.mock("flatpickr", () => ({ default: {} }));
const toasts = [];
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show: () => toasts.push(true) }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

// `import "flatpickr"` normally adds this to every element; the options are kept per element id.
const pickers = {};
const pickerOptions = {};
HTMLElement.prototype.flatpickr = function (options) {
  const picker = {
    selectedDates: [],
    input: { value: "" },
    altInput: document.createElement("input"),
    destroy() {},
    setDate: vi.fn(function (value) {
      this.selectedDates = value ? [new Date(value)] : [];
    }),
  };
  pickers[this.id] = picker;
  pickerOptions[this.id] = options;
  return picker;
};

// The calendar element carries its words from the locale files, as the server renders it.
const PAGE = `
<div id="booked-calendar" ${textsAttribute()}></div>
<div id="booking_toast" data-failed-title="Booking failed"
  data-updated-title="Booking updated" data-updated="Saved."
  data-feed="Not loaded"><div class="toast-header"></div>
<span id="toast_title"></span><span id="toast_text"></span></div>
<div id="bookModal" style="display:none">
  <h5 id="bookingModalLabel"></h5>
  <input id="sub_space_booking_id" value="12">
  <input id="book-name" value="Meeting">
  <textarea id="book-description">Weekly</textarea>
  <input id="book-start"><input id="book-end">
  <select id="subspace"><option value="4">Four</option><option value="9" selected>Nine</option></select>
  <span id="subspace_header"></span>
  <input type="checkbox" id="book-recurring"><label id="book-recurring-label"></label>
  <input id="book-recurring-end"><label id="book-recurring-end-label"></label>
  <select id="book-recurring-type"><option value="weekly">weekly</option></select>
  <label id="book-recurring-type-label"></label>
  <input type="checkbox" id="book-blocking">
  <div id="end-date-validation" class="d-none"></div>
  <button id="bookSave"></button><button id="bookUpdate"></button>
  <button id="bookDelete"></button>
  <div id="bookDeleteRecurringDropdown"></div>
  <button id="bookRecurringDeleteOne"></button>
  <button id="bookRecurringDeleteRest"></button>
  <button id="bookCancel"></button><button id="bookClose"></button>
</div>`;

const requests = [];
function answerWith(response) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (request) => {
      requests.push({
        url: new URL(request.url).pathname,
        method: request.method,
        headers: Object.fromEntries(
          [...request.headers.entries()].map(([k, v]) => [k.toLowerCase(), v]),
        ),
        body: await request.clone().text(),
      });
      if (response instanceof Error) throw response;
      return response;
    }),
  );
}

const reply = (status, body) => ({
  ok: status < 400,
  status,
  headers: new Headers(),
  text: async () => body,
});
const json = (status, value) => reply(status, JSON.stringify(value));

const flush = () => new Promise((r) => setTimeout(r, 0));
const $ = (id) => document.getElementById(id);
const modalOpen = () => $("bookModal").classList.contains("show");
const feedback = () =>
  [...document.querySelectorAll(".invalid-feedback")].map((el) => [
    el.previousElementSibling.id,
    el.innerText,
  ]);

async function boot(url = "http://localhost/sub_space_booking?room=4") {
  window.happyDOM.setURL(url);
  document.body.innerHTML = withControllers(PAGE);
  calendars.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  await settle();
  return calendars[0];
}

let reload;
// Opens the new-booking modal with valid dates and clicks Book.
async function book(response) {
  const cal = await boot();
  cal.options.customButtons.book.click();
  pickers["book-start"].setDate("2026-11-02T10:00");
  pickers["book-end"].setDate("2026-11-02T11:00");
  pickers["book-start"].input.value = "2026-11-02 10:00";
  pickers["book-end"].input.value = "2026-11-02 11:00";
  answerWith(response);
  reload = vi.spyOn(window.location, "reload").mockImplementation(() => {});
  $("bookSave").click();
  await flush();
  return cal;
}

await startBookingControllers();

beforeEach(() => {
  vi.restoreAllMocks();
  requests.length = 0;
  toasts.length = 0;
  window.scrollTo = vi.fn();
});

describe("the requests the modal sends", () => {
  const JSON_HEADERS = {
    "content-type": "application/json",
    accept: "application/json",
    "x-csrf-token": "tok",
  };

  it("posts a new booking with JSON headers and the form's values", async () => {
    await book(json(200, {}));
    expect(requests).toEqual([
      {
        url: "/sub_space_booking",
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          sub_space_booking: {
            name: "Meeting",
            description: "Weekly",
            start_time: "2026-11-02 10:00",
            end_time: "2026-11-02 11:00",
            sub_space_id: "4",
            recurring: false,
            recurring_frequency: "weekly",
            blocking: false,
          },
        }),
      },
    ]);
  });

  it("patches an update with JSON headers and the chosen room", async () => {
    await boot();
    pickers["book-start"].setDate("2026-11-02T10:00");
    pickers["book-end"].setDate("2026-11-02T11:00");
    answerWith(json(200, {}));
    $("bookUpdate").click();
    await flush();
    expect(requests).toEqual([
      {
        url: "/sub_space_booking/12/update",
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          sub_space_booking: {
            name: "Meeting",
            description: "Weekly",
            start_time: "",
            end_time: "",
            sub_space_id: "9",
            blocking: false,
          },
        }),
      },
    ]);
  });

  it.each([
    ["bookDelete", "/sub_space_booking/12/delete/12"],
    ["bookRecurringDeleteOne", "/sub_space_booking/12/delete/12"],
    [
      "bookRecurringDeleteRest",
      "/sub_space_booking/12/delete_remaining_recurring",
    ],
  ])("%s sends a DELETE with no body", async (button, url) => {
    await boot();
    answerWith(json(200, {}));
    $(button).dispatchEvent(new CustomEvent("confirmation:confirmed"));
    await flush();
    expect(requests).toEqual([
      { url, method: "DELETE", headers: JSON_HEADERS, body: "" },
    ]);
  });
});

describe("the answer to a save", () => {
  it("reloads the page after an OK answer that is not JSON", async () => {
    const cal = await book(reply(200, ""));
    expect(reload).toHaveBeenCalledTimes(1);
    expect(cal.refetched).toBe(1);
    expect(modalOpen()).toBe(false);
  });

  it("does not reload after an OK JSON answer", async () => {
    await book(json(200, { status: "ok" }));
    expect(reload).not.toHaveBeenCalled();
    expect(toasts).toHaveLength(0);
  });

  it("keeps the form and enables the button again for a refusal with no field errors", async () => {
    const cal = await book(json(403, { error: "Not allowed." }));
    expect($("toast_title").innerText).toBe("Booking failed");
    expect($("toast_text").innerText).toBe("Not allowed.");
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
    expect(modalOpen()).toBe(true);
    expect(cal.refetched).toBe(0);
  });

  it("treats a partly booked series the same whatever the status", async () => {
    const cal = await book(
      json(200, { errors: ["TimeSlot taken"], booked: 1, summary: "1 of 3" }),
    );
    expect($("toast_text").innerText).toBe("1 of 3");
    expect(cal.refetched).toBe(1);
    expect(modalOpen()).toBe(false);
    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
    // closing the modal enables its buttons again
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });

  it("shows field errors for a refusal that booked nothing", async () => {
    const cal = await book(
      json(422, { errors: ["Name can't be blank"], booked: 0 }),
    );
    expect(feedback()).toEqual([["book-name", "can't be blank"]]);
    expect(modalOpen()).toBe(true);
    expect(cal.refetched).toBe(0);
    expect(toasts).toHaveLength(0);
  });

  it("marks a field once, shows a bare word as its own text and skips unknown fields", async () => {
    await book(
      json(422, {
        errors: [
          "Name can't be blank",
          "Name is too short",
          "Description",
          "Colour is wrong",
        ],
      }),
    );
    expect(feedback()).toEqual([
      ["book-name", "can't be blank"],
      ["book-description", "Description"],
    ]);
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });

  it.each(["DurationHour", "DurationWeek", "TimeSlot"])(
    "a %s error is a toast that closes the modal, after earlier field marks",
    async (rule) => {
      await book(
        json(422, { errors: ["Name can't be blank", `${rule} Too much.`] }),
      );
      expect($("toast_title").innerText).toBe("Booking failed");
      expect($("toast_text").innerText).toBe("Too much.");
      expect(modalOpen()).toBe(false);
      expect(feedback()).toEqual([]);
      expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
    },
  );

  it.each([
    ["Recurring Choose an end date.", "book-recurring", "Choose an end date."],
    ["Start time is in the past", "book-start", "time is in the past"],
  ])(
    "an error coded %s marks the field of that name",
    async (error, field, text) => {
      const cal = await book(json(422, { errors: [error] }));
      expect(feedback()).toEqual([[field, text]]);
      expect($(field).classList.contains("is-invalid")).toBe(true);
      expect(modalOpen()).toBe(true);
      expect(toasts).toHaveLength(0);
      expect(cal.refetched).toBe(0);
    },
  );

  it("does nothing more for an empty error list", async () => {
    const cal = await book(json(422, { errors: [] }));
    expect(modalOpen()).toBe(true);
    expect(toasts).toHaveLength(0);
    expect(cal.refetched).toBe(0);
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });

  it("shows the generic text when handling the answer fails", async () => {
    document.documentElement.dataset.requestFailed = "No reason given";
    const cal = await boot();
    cal.refetchEvents = () => {
      throw new Error("calendar gone");
    };
    cal.options.customButtons.book.click();
    answerWith(json(200, {}));
    $("bookSave").click();
    await flush();
    expect($("toast_title").innerText).toBe("Booking failed");
    expect($("toast_text").innerText).toBe("No reason given");
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });
});

describe("each Turbo visit", () => {
  // The shown format and the locale now come from the page's language (page_locale.js).
  const DATE_TIME = { enableTime: true, time_24hr: true, altInput: true };

  it("sets up the pickers with their options", async () => {
    await boot();
    expect(pickerOptions["book-start"]).toMatchObject(DATE_TIME);
    expect(pickerOptions["book-end"]).toMatchObject(DATE_TIME);
    expect(pickerOptions["book-recurring-end"]).toMatchObject({
      enableTime: false,
      altInput: true,
    });
  });

  it("builds the calendar in the Toronto time zone with the page's options", async () => {
    const cal = await boot(
      "http://localhost/sub_space_booking?room=4&start=2026-03-02",
    );
    const { options } = cal;
    expect(options).toMatchObject({
      timeZone: "America/Toronto",
      firstDay: 0,
      scrollTime: "07:00:00",
      height: "auto",
      headerToolbar: {
        left: "prev,today,next",
        center: "",
        right: "book,timeGridWeek",
      },
      views: {
        timeGridWeek: {
          dayHeaderFormat: { weekday: "short", day: "numeric", month: "short" },
        },
      },
      allDaySlot: false,
      initialView: "timeGridWeek",
      navLinks: true,
      slotEventOverlap: false,
      slotMinTime: "06:00:00",
      slotMaxTime: "22:00:00",
      selectable: true,
      eventTimeFormat: { hour: "2-digit", minute: "2-digit", hour12: false },
      dayMaxEvents: true,
    });
    expect(options.initialDate.toISOString()).toBe("2026-03-02T00:00:00.000Z");
    expect(options.eventSources).toHaveLength(1);
    expect(options.eventSources[0]).toMatchObject({
      id: "booked",
      url: "/sub_space_booking/bookings?room=4",
    });
    expect(options.plugins.slice(-2)).toEqual([
      { name: "interaction" },
      { name: "list" },
    ]);
  });

  it("builds a fresh calendar and sends to it after a new visit", async () => {
    const first = await boot();
    const second = await boot();
    expect(second).not.toBe(first);
    second.options.customButtons.book.click();
    answerWith(json(200, {}));
    $("bookSave").click();
    await flush();
    expect(second.refetched).toBe(1);
    expect(first.refetched).toBe(0);
  });

  it("fills the recurring approval modal when it has no select buttons", async () => {
    document.body.innerHTML = withControllers(
      `<div id="approveRecurringModal"><div id="recurring-checkboxes"></div></div>`,
    );
    document.dispatchEvent(new Event("turbo:load"));
    await settle();
    const trigger = document.createElement("button");
    trigger.dataset.dates = JSON.stringify([[5, "Fri"]]);
    const event = new Event("show.bs.modal");
    event.relatedTarget = trigger;
    $("approveRecurringModal").dispatchEvent(event);
    expect($("rc_5").checked).toBe(true);
    expect(document.querySelector("label[for=rc_5]").textContent).toBe("Fri");
  });
});
