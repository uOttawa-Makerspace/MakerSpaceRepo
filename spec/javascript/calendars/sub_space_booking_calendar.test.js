// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

// A stand-in for FullCalendar: records the options and counts refetches.
const calendars = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = options;
      this.refetched = 0;
      this.rendered = false;
      calendars.push(this);
    }
    refetchEvents() {
      this.refetched++;
    }
    render() {
      this.rendered = true;
    }
  },
}));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("tom-select", () => ({
  default: class {
    constructor() {
      this.hook = () => {};
    }
  },
}));
vi.mock("flatpickr", () => ({ default: {} }));

const shown = [];
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show: () => shown.push(true) }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

// `import "flatpickr"` normally adds this to every element.
const pickers = {};
HTMLElement.prototype.flatpickr = function () {
  const picker = {
    selectedDates: [],
    input: { value: "" },
    altInput: document.createElement("input"),
    setDate: vi.fn(function (value) {
      this.selectedDates = value ? [new Date(value)] : [];
    }),
  };
  pickers[this.id] = picker;
  return picker;
};

const PAGE = `
<div id="booked-calendar"></div>
<div id="booking_toast" data-failed-title="Booking failed"
  data-feed="The bookings could not be loaded."
  data-unavailable-title="Booking unavailable"
  data-unavailable="This booking could not be opened."></div><span id="toast_title"></span><span id="toast_text"></span>
<div id="bookModal" style="display:none">
  <h5 id="bookingModalLabel"></h5>
  <input id="sub_space_booking_id">
  <input id="book-name" value="Meeting">
  <textarea id="book-description">Weekly</textarea>
  <input id="book-start"><input id="book-end">
  <select id="subspace"><option value="4">Four</option><option value="9">Nine</option></select>
  <span id="subspace_header"></span>
  <input type="checkbox" id="book-recurring"><label id="book-recurring-label"></label>
  <input id="book-recurring-end"><label id="book-recurring-end-label"></label>
  <select id="book-recurring-type"><option value="weekly">weekly</option></select>
  <label id="book-recurring-type-label"></label>
  <input type="checkbox" id="book-blocking">
  <input class="flatpickr">
  <div id="end-date-validation" class="d-none"></div>
  <button id="bookSave"></button><button id="bookUpdate"></button>
  <button id="bookDelete"></button>
  <div id="bookDeleteRecurringDropdown"></div>
  <button id="bookRecurringDeleteOne"></button>
  <button id="bookRecurringDeleteRest"></button>
  <button id="bookCancel"></button><button id="bookClose"></button>
</div>`;

const requests = [];
function stubFetch(handler) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (request, init) => {
      const isRequest = typeof request !== "string";
      const url = isRequest ? request.url : request;
      requests.push({
        url:
          new URL(url, "http://localhost").pathname +
          new URL(url, "http://localhost").search,
        method: isRequest ? request.method : (init?.method ?? "GET"),
        body: isRequest ? await request.clone().text() : undefined,
        headers: isRequest ? request.headers : new Headers(init?.headers),
      });
      return handler(url);
    }),
  );
}

const reply = (
  body,
  { ok = true, status = 200, type = "application/json" } = {},
) => ({
  ok,
  status,
  headers: {
    get: (name) => (name.toLowerCase() === "content-type" ? type : null),
  },
  text: async () => body,
  json: async () => JSON.parse(body),
});

const flush = () => new Promise((r) => setTimeout(r, 0));
const $ = (id) => document.getElementById(id);

function boot(url = "http://localhost/sub_space_booking?room=4", page = PAGE) {
  window.happyDOM.setURL(url);
  document.body.innerHTML = page;
  calendars.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  return calendars[0];
}

function pickDates(start, end) {
  pickers["book-start"].setDate(start);
  pickers["book-end"].setDate(end);
  pickers["book-start"].input.value = start;
  pickers["book-end"].input.value = end;
}

await import("../../../app/javascript/entrypoints/sub_space_booking.js");

beforeEach(() => {
  requests.length = 0;
  shown.length = 0;
  for (const key of Object.keys(pickers)) delete pickers[key];
  window.scrollTo = vi.fn();
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("calendar page", () => {
  it("renders the calendar for the room in the address", () => {
    const cal = boot("http://localhost/sub_space_booking?room=4");
    expect(cal.rendered).toBe(true);
    expect(cal.options.eventSources[0].url).toBe(
      "/sub_space_booking/bookings?room=4",
    );
  });

  it("opens on the date named by the start parameter", () => {
    const cal = boot(
      "http://localhost/sub_space_booking?room=4&start=2026-03-02",
    );
    expect(cal.options.initialDate.toISOString()).toBe(
      "2026-03-02T00:00:00.000Z",
    );
  });

  it("says when the bookings could not be loaded", async () => {
    const cal = boot();
    await cal.options.eventSources[0].failure(new Error("feed down"));
    expect($("toast_title").innerText).toBe("Booking failed");
    expect($("toast_text").innerText).toBe("The bookings could not be loaded.");
  });

  it("does nothing more on a page without the calendar", () => {
    const cal = boot("http://localhost/sub_space_booking", "<p>x</p>");
    expect(cal).toBeUndefined();
  });
});

describe("new booking", () => {
  it("the Book button opens the modal for a new booking", () => {
    const cal = boot();
    cal.options.customButtons.book.click();

    expect($("bookModal").classList.contains("show")).toBe(true);
    expect($("bookingModalLabel").innerText).toBe("New Booking");
    expect($("bookSave").style.display).toBe("block");
    expect($("bookUpdate").style.display).toBe("none");
    expect($("bookDelete").style.display).toBe("none");
    expect($("subspace").style.display).toBe("none");
    expect(document.getElementById("book-modal-backdrop")).not.toBeNull();
    expect($("book-recurring-end").style.display).toBe("none");
  });

  it("selecting a range fills the start and end", () => {
    const cal = boot();
    cal.options.select({
      startStr: "2026-11-02T10:00:00",
      endStr: "2026-11-02T11:00:00",
    });
    expect(pickers["book-start"].setDate).toHaveBeenCalledWith(
      Date.parse("2026-11-02T10:00:00"),
    );
    expect(pickers["book-end"].setDate).toHaveBeenCalledWith(
      Date.parse("2026-11-02T11:00:00"),
    );
  });

  it("ticking recurring shows the recurrence fields", () => {
    const cal = boot();
    cal.options.customButtons.book.click();
    $("book-recurring").checked = true;
    $("book-recurring").dispatchEvent(new Event("change"));
    expect($("book-recurring-end").style.display).toBe("block");
    expect($("book-recurring-type").style.display).toBe("block");
    expect(document.querySelector(".flatpickr").style.display).toBe("block");
  });

  it("refuses an end before the start and sends nothing", () => {
    const cal = boot();
    stubFetch(() => reply("{}"));
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T11:00", "2026-11-02T10:00");

    $("bookSave").click();

    expect($("end-date-validation").classList.contains("d-none")).toBe(false);
    expect(pickers["book-end"].altInput.classList.contains("is-invalid")).toBe(
      true,
    );
    expect(requests).toEqual([]);
  });

  it("posts the booking and refreshes the calendar", async () => {
    const cal = boot();
    stubFetch(() => reply("{}"));
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T10:00", "2026-11-02T11:00");
    $("book-blocking").checked = true;

    $("bookSave").click();
    expect($("bookSave").hasAttribute("disabled")).toBe(true);
    await flush();

    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({
      url: "/sub_space_booking",
      method: "POST",
    });
    expect(requests[0].headers.get("X-CSRF-Token")).toBe("tok");
    expect(JSON.parse(requests[0].body).sub_space_booking).toMatchObject({
      name: "Meeting",
      description: "Weekly",
      start_time: "2026-11-02T10:00",
      end_time: "2026-11-02T11:00",
      sub_space_id: "4",
      recurring: false,
      recurring_frequency: "weekly",
      blocking: true,
    });
    expect(cal.refetched).toBe(1);
    expect($("bookModal").classList.contains("show")).toBe(false);
    expect($("book-name").value).toBe("");
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });

  it("marks the field a validation error names", async () => {
    const cal = boot();
    stubFetch(() =>
      reply(
        JSON.stringify({
          errors: ["Name can't be blank", "Description is too long"],
        }),
      ),
    );
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T10:00", "2026-11-02T11:00");

    $("bookSave").click();
    await flush();

    expect($("book-name").classList.contains("is-invalid")).toBe(true);
    expect($("book-name").nextElementSibling.textContent).toBe(
      "can't be blank",
    );
    expect($("book-description").classList.contains("is-invalid")).toBe(true);
    expect($("bookSave").hasAttribute("disabled")).toBe(false);
    expect($("bookModal").classList.contains("show")).toBe(true);
    expect(cal.refetched).toBe(0);
  });

  it("shows a toast and closes the modal for a slot rule error", async () => {
    const cal = boot();
    stubFetch(() =>
      reply(JSON.stringify({ errors: ["TimeSlot is already taken"] })),
    );
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T10:00", "2026-11-02T11:00");

    $("bookSave").click();
    await flush();

    expect($("toast_title").innerText).toBe("Booking failed");
    expect($("toast_text").innerText).toBe("is already taken");
    expect(shown).toHaveLength(1);
    expect($("bookModal").classList.contains("show")).toBe(false);
    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
  });

  it("reports a partly booked series and refreshes the calendar", async () => {
    const cal = boot();
    stubFetch(() =>
      reply(
        JSON.stringify({
          errors: ["TimeSlot taken"],
          booked: 2,
          summary: "2 of 4 booked",
        }),
        { ok: false, status: 422 },
      ),
    );
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T10:00", "2026-11-02T11:00");

    $("bookSave").click();
    await flush();

    expect($("toast_title").innerText).toBe("Booking partly done");
    expect($("toast_text").innerText).toBe("2 of 4 booked");
    expect(cal.refetched).toBe(1);
    expect($("bookModal").classList.contains("show")).toBe(false);
  });

  it("enables the button again when the request fails", async () => {
    const cal = boot();
    stubFetch(() => {
      throw new Error("offline");
    });
    cal.options.customButtons.book.click();
    pickDates("2026-11-02T10:00", "2026-11-02T11:00");

    $("bookSave").click();
    await flush();

    expect($("bookSave").hasAttribute("disabled")).toBe(false);
  });

  it("cancel and close reset the modal", () => {
    const cal = boot();
    cal.options.customButtons.book.click();
    $("book-name").classList.add("is-invalid");
    $("bookCancel").click();
    expect($("bookModal").style.display).toBe("none");
    expect($("book-name").value).toBe("");
    expect($("book-name").classList.contains("is-invalid")).toBe(false);
    expect(document.getElementById("book-modal-backdrop")).toBeNull();

    cal.options.customButtons.book.click();
    $("bookClose").click();
    expect($("bookModal").classList.contains("show")).toBe(false);
  });
});

describe("existing booking", () => {
  const booking = (extra = {}) => ({
    name: "Standup",
    description: "Daily",
    start_time: "2026-11-02T10:00:00-05:00",
    end_time: "2026-11-02T11:00:00-05:00",
    blocking: true,
    recurring_booking_id: null,
    // a string: the DOM test environment does not turn a number into an option value
    sub_space_id: "9",
    ...extra,
  });
  const click = (cal, viewable = true) =>
    cal.options.eventClick({
      event: { id: "booking_12", extendedProps: { viewable } },
    });

  it("ignores an event the user may not open", () => {
    const cal = boot();
    stubFetch(() => reply("{}"));
    click(cal, false);
    expect(requests).toEqual([]);
    expect($("bookModal").classList.contains("show")).toBe(false);
  });

  it("loads the booking into the modal", async () => {
    const cal = boot();
    stubFetch(() => reply(JSON.stringify(booking())));
    click(cal);
    await flush();

    expect(requests[0].url).toBe(
      "/sub_space_booking/get_sub_space_booking?id=12",
    );
    expect($("sub_space_booking_id").value).toBe("12");
    expect($("book-name").value).toBe("Standup");
    expect($("book-description").value).toBe("Daily");
    expect($("book-blocking").checked).toBe(true);
    expect($("subspace").value).toBe("9");
    expect($("bookingModalLabel").innerText).toBe("Update Booking");
    expect($("bookUpdate").style.display).toBe("block");
    expect($("bookSave").style.display).toBe("none");
    expect($("bookDelete").style.display).toBe("block");
    expect($("bookDeleteRecurringDropdown").style.display).toBe("none");
    expect($("bookModal").classList.contains("show")).toBe(true);
    expect(pickers["book-start"].setDate).toHaveBeenCalledWith(
      Date.parse("2026-11-02T10:00:00"),
    );
  });

  it("offers the series delete for a recurring booking", async () => {
    const cal = boot();
    stubFetch(() =>
      reply(JSON.stringify(booking({ recurring_booking_id: 3 }))),
    );
    click(cal);
    await flush();
    expect($("bookDelete").style.display).toBe("none");
    expect($("bookDeleteRecurringDropdown").style.display).toBe("block");
  });

  it.each([
    ["a server error", reply("boom", { ok: false, status: 500 })],
    ["a page that is not JSON", reply("<html>", { type: "text/html" })],
  ])("says the booking is unavailable on %s", async (_name, response) => {
    const cal = boot();
    stubFetch(() => response);
    click(cal);
    await flush();
    expect($("toast_title").innerText).toBe("Booking unavailable");
    expect($("toast_text").innerText).toBe("This booking could not be opened.");
    expect($("bookModal").classList.contains("show")).toBe(false);
  });

  it("patches the booking", async () => {
    const cal = boot();
    stubFetch(() => reply(JSON.stringify(booking())));
    click(cal);
    await flush();
    pickDates("2026-11-02T10:00", "2026-11-02T12:00");
    requests.length = 0;
    stubFetch(() => reply("{}"));

    $("bookUpdate").click();
    await flush();

    expect(requests[0]).toMatchObject({
      url: "/sub_space_booking/12/update",
      method: "PATCH",
    });
    expect(JSON.parse(requests[0].body).sub_space_booking).toMatchObject({
      name: "Standup",
      sub_space_id: "9",
      end_time: "2026-11-02T12:00",
    });
    expect(cal.refetched).toBe(1);
  });

  it("does not patch when the dates are invalid", async () => {
    const cal = boot();
    stubFetch(() => reply(JSON.stringify(booking())));
    click(cal);
    await flush();
    pickDates("2026-11-02T12:00", "2026-11-02T10:00");
    requests.length = 0;

    $("bookUpdate").click();
    expect(requests).toEqual([]);
  });

  it("deletes after confirmation and not without it", async () => {
    const cal = boot();
    stubFetch(() => reply(JSON.stringify(booking())));
    click(cal);
    await flush();
    requests.length = 0;
    stubFetch(() => reply("{}"));

    vi.stubGlobal("confirm", () => false);
    $("bookDelete").click();
    expect(requests).toEqual([]);

    vi.stubGlobal("confirm", () => true);
    $("bookDelete").click();
    await flush();
    expect(requests[0]).toMatchObject({
      url: "/sub_space_booking/12/delete/12",
      method: "DELETE",
    });
    expect(cal.refetched).toBe(1);
  });

  it("deletes the rest of a series after confirmation", async () => {
    const cal = boot();
    stubFetch(() =>
      reply(JSON.stringify(booking({ recurring_booking_id: 3 }))),
    );
    click(cal);
    await flush();
    requests.length = 0;
    stubFetch(() => reply("{}"));

    vi.stubGlobal("confirm", () => false);
    $("bookRecurringDeleteRest").click();
    expect(requests).toEqual([]);

    vi.stubGlobal("confirm", () => true);
    $("bookRecurringDeleteRest").click();
    await flush();
    expect(requests[0]).toMatchObject({
      url: "/sub_space_booking/12/delete_remaining_recurring",
      method: "DELETE",
    });

    requests.length = 0;
    $("bookRecurringDeleteOne").click();
    await flush();
    expect(requests[0].url).toBe("/sub_space_booking/12/delete/12");
  });
});

describe("admin lists", () => {
  it("fills the recurring approval modal with one checked box per date", () => {
    boot(
      "http://localhost/sub_space_booking",
      `<div id="approveRecurringModal">
         <div id="recurring-checkboxes"></div>
         <button id="recurringSelectAll"></button><button id="recurringSelectNone"></button>
       </div>`,
    );
    const trigger = document.createElement("button");
    trigger.dataset.dates = JSON.stringify([
      [1, "Mon"],
      [2, "Tue"],
    ]);
    const event = new Event("show.bs.modal");
    event.relatedTarget = trigger;
    $("approveRecurringModal").dispatchEvent(event);

    const boxes = [...document.querySelectorAll("#recurring-checkboxes input")];
    expect(boxes.map((b) => b.value)).toEqual(["1", "2"]);
    expect(boxes.every((b) => b.checked)).toBe(true);

    $("recurringSelectNone").click();
    expect(boxes.some((b) => b.checked)).toBe(false);
    $("recurringSelectAll").click();
    expect(boxes.every((b) => b.checked)).toBe(true);
  });

  it.each([
    ["pending_bookings_select_all", "pending-booking-select"],
    ["userRequestSelectAll", "user-request-select"],
  ])("%s selects and clears every row", (allId, rowClass) => {
    boot(
      "http://localhost/sub_space_booking",
      `<input type="checkbox" id="${allId}">
       <input type="checkbox" class="${rowClass}"><input type="checkbox" class="${rowClass}">`,
    );
    const all = $(allId);
    const rows = document.querySelectorAll(`.${rowClass}`);

    all.checked = true;
    all.dispatchEvent(new Event("change"));
    expect([...rows].every((r) => r.checked)).toBe(true);

    all.checked = false;
    all.dispatchEvent(new Event("change"));
    expect([...rows].some((r) => r.checked)).toBe(false);
  });

  it("shows the supervisor list only for the Staff identity", () => {
    boot(
      "http://localhost/sub_space_booking",
      `<button class="identity-button" value="Staff" id="staff"></button>
       <button class="identity-button" value="Student" id="student"></button>
       <div id="supervisor-select"></div>`,
    );
    $("staff").click();
    expect($("supervisor-select").style.display).toBe("block");
    $("student").click();
    expect($("supervisor-select").style.display).toBe("none");
  });
});
