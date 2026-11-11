// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

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
const eventClick = vi.fn();
const eventCreate = vi.fn();
const addUnavailabilityClick = vi.fn();
vi.mock("../../../app/javascript/src/unavailabilities_helpers.js", () => ({
  eventClick,
  eventCreate,
  addUnavailabilityClick,
}));

const { default: UnavailabilitiesCalendar } =
  await import("../../../app/javascript/controllers/unavailabilities_calendar_controller.js");

const PAGE = `
<div data-controller="unavailabilities-calendar">
  <div id="calendar_container" data-unavailabilities-calendar-target="container" style="display:none">
    <button id="addUnavailabilityButton" data-action="click->unavailabilities-calendar#addUnavailability"></button>
    <div id="calendar" data-unavailabilities-calendar-target="calendar"><p id="stale">old</p></div>
  </div>
  <div id="spinner_container" data-unavailabilities-calendar-target="spinner"></div>
</div>`;

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
let application;

async function boot(html = PAGE) {
  document.body.innerHTML = html;
  created.length = 0;
  application = Application.start();
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
    expect(cal.options.events).toBe("/staff/unavailabilities/json");
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

  it("puts the dialog in add mode when the add button is clicked", async () => {
    addUnavailabilityClick.mockClear();
    await boot();
    document.getElementById("addUnavailabilityButton").click();
    expect(addUnavailabilityClick).toHaveBeenCalledTimes(1);
  });

  it("opens the unavailability dialog for a clicked event and a selected range", async () => {
    const cal = await boot();
    cal.options.eventClick({ event: { id: "e" } });
    cal.options.select({ startStr: "s" });
    expect(eventClick).toHaveBeenCalledWith({ id: "e" });
    expect(eventCreate).toHaveBeenCalledWith({ startStr: "s" });
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
