// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const calendars = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = options;
      this.rendered = false;
      calendars.push(this);
    }
    render() {
      this.rendered = true;
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
vi.mock("../../../app/javascript/src/unavailabilities_helpers.js", () => ({
  eventClick,
  eventCreate,
}));

await import("../../../app/javascript/src/fullcalendar_setup_staff_unavailabilities.js");

function boot() {
  document.body.innerHTML = `<div id="calendar_container" style="display:none"></div>
    <div id="spinner_container"></div><div id="calendar"></div>`;
  calendars.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  return calendars[0];
}

beforeEach(() => {
  localStorage.clear();
  globalThis.requestAnimationFrame = (fn) => fn();
});

describe("staff unavailabilities calendar", () => {
  it("reads the staff member's own unavailabilities and shows the calendar", () => {
    const cal = boot();
    expect(cal.options.events).toBe("/staff/unavailabilities/json");
    expect(cal.rendered).toBe(true);
    expect(document.getElementById("calendar_container").style.display).toBe(
      "block",
    );
    expect(document.getElementById("spinner_container").style.display).toBe(
      "none",
    );
  });

  it("opens the unavailability dialog for a clicked event and a selected range", () => {
    const cal = boot();
    cal.options.eventClick({ event: { id: "e" } });
    cal.options.select({ startStr: "s" });
    expect(eventClick).toHaveBeenCalledWith({ id: "e" });
    expect(eventCreate).toHaveBeenCalledWith({ startStr: "s" });
  });

  it("makes the calendar accessible whenever a view is mounted", () => {
    const cal = boot();
    cal.options.viewDidMount();
    expect(accessible).toHaveBeenCalledWith(
      document.getElementById("calendar"),
    );
  });

  it("fades events in", () => {
    const cal = boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({ el });
    expect(el.classList.contains("fade-in")).toBe(true);
  });

  it("remembers the first day of the view and opens there next time", () => {
    const cal = boot();
    cal.options.datesSet({
      view: { currentStart: new Date("2026-11-02T00:00:00Z") },
    });
    expect(localStorage.fullCalendarDefaultDateStaffUnavailabilities).toBe(
      "2026-11-02T00:00:00.000Z",
    );
    expect(boot().options.initialDate).toBe("2026-11-02T00:00:00.000Z");
  });
});
