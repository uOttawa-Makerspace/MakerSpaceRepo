// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application, Controller } from "@hotwired/stimulus";

const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = options;
      this.rendered = false;
      this.destroyed = false;
      created.push(this);
    }
    render() {
      this.rendered = true;
    }
    destroy() {
      this.destroyed = true;
    }
  },
}));
vi.mock("@fullcalendar/rrule", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));

const accessible = vi.fn();
vi.mock("../../../app/javascript/src/calendar_accessibility.js", () => ({
  makeCalendarAccessible: accessible,
}));
const details = { show: vi.fn() };
const form = {
  openForAdd: vi.fn(),
  openForEdit: vi.fn(),
  openForRange: vi.fn(),
};

const { default: UnavailabilitiesCalendar } =
  await import("../../../app/javascript/controllers/unavailabilities_calendar_controller.js");

const PAGE = `
<div data-controller="unavailabilities-calendar" data-unavailabilities-calendar-feed-url-value="/staff/unavailabilities/json" data-unavailabilities-calendar-failure-template-value="{host} could not be loaded" data-unavailabilities-calendar-unknown-host-value="a linked calendar" data-unavailabilities-calendar-feed-failure-value="Your calendar could not be loaded" data-unavailabilities-calendar-unavailability-form-outlet="#modal" data-unavailabilities-calendar-imported-event-details-outlet="#details">
  <div id="calendar_container" data-unavailabilities-calendar-target="container" style="display:none">
    <button id="addUnavailabilityButton" data-action="click->unavailabilities-calendar#addUnavailability"></button>
    <div id="calendar" data-unavailabilities-calendar-target="calendar"><p id="stale">old</p></div>
  </div>
  <div id="spinner_container" data-unavailabilities-calendar-target="spinner"></div>
  <div id="failures" data-unavailabilities-calendar-target="failures" hidden></div>
</div>
<div id="modal" data-controller="unavailability-form"></div>
<div id="details" data-controller="imported-event-details"></div>`;

class FakeForm extends Controller {
  openForAdd(options) {
    form.openForAdd(options);
  }
  openForEdit(event) {
    form.openForEdit(event);
  }
  openForRange(range) {
    form.openForRange(range);
  }
}

class FakeDetails extends Controller {
  show(event, returnFocusTo) {
    details.show(event, returnFocusTo);
  }
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
let application;

async function boot(html = PAGE) {
  document.body.innerHTML = html;
  created.length = 0;
  application = Application.start();
  application.register("unavailability-form", FakeForm);
  application.register("imported-event-details", FakeDetails);
  application.register("unavailabilities-calendar", UnavailabilitiesCalendar);
  await settle();
  return created[0];
}

beforeEach(() => {
  localStorage.clear();
  globalThis.requestAnimationFrame = (fn) => fn();
});

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
});

describe("staff unavailabilities calendar", () => {
  it("does nothing on a page without its element", async () => {
    await boot('<div id="calendar"></div>');
    document.dispatchEvent(new Event("turbo:load"));
    expect(created).toHaveLength(0);
  });

  it("draws once, clears markup left by a cached page, and shows the calendar", async () => {
    const cal = await boot();
    expect(created).toHaveLength(1);
    expect(document.getElementById("stale")).toBeNull();
    document.dispatchEvent(new Event("turbo:load"));
    expect(created).toHaveLength(1);
    expect(cal.options.events.url).toBe("/staff/unavailabilities/json");
    expect(cal.rendered).toBe(true);
    expect(document.getElementById("calendar_container").style.display).toBe(
      "block",
    );
    expect(document.getElementById("spinner_container").style.display).toBe(
      "none",
    );
  });

  it("destroys the calendar when the element leaves the page", async () => {
    const cal = await boot();
    document.body.innerHTML = "";
    await settle();
    expect(cal.destroyed).toBe(true);
  });

  it("opens the dialog in add mode when the add button is clicked", async () => {
    form.openForAdd.mockClear();
    await boot();
    document.getElementById("addUnavailabilityButton").click();
    expect(form.openForAdd).toHaveBeenCalledTimes(1);
    expect(form.openForAdd).toHaveBeenCalledWith({
      returnFocusTo: document.getElementById("addUnavailabilityButton"),
    });
  });

  it("opens the unavailability dialog for a clicked event and a selected range", async () => {
    const cal = await boot();
    const own = { id: "e", extendedProps: { eventType: "unavailability" } };
    cal.options.eventClick({ event: own });
    cal.options.select({ startStr: "s", endStr: "t" });
    expect(form.openForEdit).toHaveBeenCalledWith(own);
    expect(form.openForRange).toHaveBeenCalledWith({ start: "s", end: "t" });
  });

  it("shows the read-only details, not the edit dialog, for an event imported from a calendar feed", async () => {
    form.openForEdit.mockClear();
    details.show.mockClear();
    const cal = await boot();
    const imported = { id: "a/../b?x#y", extendedProps: { name: "Feed" } };
    const el = document.createElement("a");
    cal.options.eventClick({ event: imported, el });
    expect(form.openForEdit).not.toHaveBeenCalled();
    expect(details.show).toHaveBeenCalledWith(imported, el);
  });

  it("does not show the imported details for the staff member's own event", async () => {
    details.show.mockClear();
    const cal = await boot();
    cal.options.eventClick({
      event: { id: "e", extendedProps: { eventType: "unavailability" } },
    });
    expect(details.show).not.toHaveBeenCalled();
  });

  describe("linked calendars that could not be loaded", () => {
    const response = (value) => ({
      headers: new Headers(
        value ? { "X-Failed-Calendars": JSON.stringify(value) } : {},
      ),
    });
    const failures = () => document.getElementById("failures");

    it("names each failed host as text and shows the area", async () => {
      const cal = await boot();
      const kept = cal.options.events.success(
        [{ id: "e" }],
        response(["a.example", "<b>b</b>.example"]),
      );
      expect(kept).toBeUndefined();
      expect(failures().hidden).toBe(false);
      expect([...failures().children].map((c) => c.textContent)).toEqual([
        "a.example could not be loaded",
        "<b>b</b>.example could not be loaded",
      ]);
      expect(failures().querySelector("b")).toBeNull();
    });

    it("names a link whose host could not be read as a linked calendar", async () => {
      const cal = await boot();
      cal.options.events.success([], response([null]));
      expect(failures().textContent).toBe(
        "a linked calendar could not be loaded",
      );
    });

    it("replaces earlier lines with one message when the feed itself fails", async () => {
      const cal = await boot();
      cal.options.events.success([], response(["a.example"]));
      cal.options.events.failure(new Error("down"));
      expect(failures().hidden).toBe(false);
      expect([...failures().children].map((c) => c.textContent)).toEqual([
        "Your calendar could not be loaded",
      ]);
    });

    it("clears the names again when every calendar loads", async () => {
      const cal = await boot();
      cal.options.events.success([], response(["a.example"]));
      cal.options.events.success([], response(null));
      expect(failures().hidden).toBe(true);
      expect(failures().children).toHaveLength(0);
    });
  });

  it("makes the calendar accessible whenever a view is mounted", async () => {
    const cal = await boot();
    cal.options.viewDidMount();
    expect(accessible).toHaveBeenCalledWith(
      document.getElementById("calendar"),
    );
  });

  it("fades events in", async () => {
    const cal = await boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({ el });
    expect(el.classList.contains("fade-in")).toBe(true);
  });

  it("remembers the first day of the view and opens there next time", async () => {
    const cal = await boot();
    cal.options.datesSet({
      view: { currentStart: new Date("2026-11-02T00:00:00Z") },
    });
    expect(localStorage.fullCalendarDefaultDateStaffUnavailabilities).toBe(
      "2026-11-02T00:00:00.000Z",
    );
    expect((await boot()).options.initialDate).toBe("2026-11-02T00:00:00.000Z");
  });
});
