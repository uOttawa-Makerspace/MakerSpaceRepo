// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = { slotEventOverlap: false, ...options };
      this.eventList = [];
      this.rendered = false;
      created.push(this);
    }
    getOption(name) {
      return this.options[name];
    }
    setOption(name, value) {
      this.options[name] = value;
    }
    getEvents() {
      return this.eventList;
    }
    getEventById(id) {
      return this.eventList.find((e) => e.id === id);
    }
    render() {
      this.rendered = true;
    }
  },
}));
vi.mock("@fullcalendar/rrule", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));

const tooltips = [];
vi.mock("bootstrap", () => ({
  Tooltip: class {
    constructor(el, options) {
      tooltips.push({ el, options });
    }
  },
}));

const PAGE = `
<input id="space_id" value="3">
<div id="calendar_container" style="display:none"></div>
<div id="spinner_container"></div>
<div id="calendar"></div>
<span class="fc-toggleOthersShifts-button"></span>
<span class="fc-toggleEventOverlap-button"></span>`;

function boot() {
  document.body.innerHTML = PAGE;
  created.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  return created[0];
}

const shift = (id, hasCurrentUser) => {
  const props = {};
  return {
    id,
    extendedProps: { hasCurrentUser },
    display: "auto",
    setProp: (name, value) => (props[name] = value),
    props,
  };
};

await import("../../../app/javascript/entrypoints/my_calendar.js");

beforeEach(() => {
  localStorage.clear();
  tooltips.length = 0;
  globalThis.requestAnimationFrame = (fn) => fn();
});

describe("my calendar", () => {
  it("reads the events of the space and shows the calendar", () => {
    const cal = boot();
    expect(cal.options.eventSources).toBe("/staff/my_calendar/json/3");
    expect(cal.rendered).toBe(true);
    expect(document.getElementById("calendar_container").style.display).toBe(
      "block",
    );
    expect(document.getElementById("spinner_container").style.display).toBe(
      "none",
    );
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Enable Event Overlap");
  });

  it("starts at the remembered date and overlap setting", () => {
    localStorage.fullCalendarEventOverlap = "true";
    localStorage.fullCalendarDefaultDateStaffCalendar = "2026-03-02T00:00:00Z";
    const cal = boot();
    expect(cal.options.slotEventOverlap).toBe(true);
    expect(cal.options.initialDate).toBe("2026-03-02T00:00:00Z");
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Disable Event Overlap");
  });

  it("remembers the first day of the view", () => {
    const cal = boot();
    cal.options.datesSet({
      view: { currentStart: new Date("2026-11-02T00:00:00Z") },
    });
    expect(localStorage.fullCalendarDefaultDateStaffCalendar).toBe(
      "2026-11-02T00:00:00.000Z",
    );
  });

  it("toggles event overlap, remembers it and relabels the button", () => {
    const cal = boot();
    cal.options.customButtons.toggleEventOverlap.click();
    expect(cal.options.slotEventOverlap).toBe(true);
    expect(localStorage.fullCalendarEventOverlap).toBe("true");
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Disable Event Overlap");

    cal.options.customButtons.toggleEventOverlap.click();
    expect(cal.options.slotEventOverlap).toBe(false);
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Enable Event Overlap");
  });

  it("hides other people's shifts, then shows them all again", () => {
    const cal = boot();
    const mine = shift("a", true);
    const theirs = shift("b", false);
    cal.eventList = [mine, theirs];

    cal.options.customButtons.toggleOthersShifts.click();
    expect(mine.props.display).toBe("auto");
    expect(theirs.props.display).toBe("none");
    expect(
      document.querySelector(".fc-toggleOthersShifts-button").innerHTML,
    ).toBe("Show All Shifts");

    cal.options.customButtons.toggleOthersShifts.click();
    expect(theirs.props.display).toBe("auto");
    expect(
      document.querySelector(".fc-toggleOthersShifts-button").innerHTML,
    ).toBe("Show My Shifts Only");
  });

  it("decorates a mounted event with a tooltip, fade in and user colour", () => {
    const cal = boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: {
        title: "Shift",
        extendedProps: { description: "Desk", background: "#ff0000" },
      },
    });
    expect(el.classList.contains("fade-in")).toBe(true);
    expect(el.getAttribute("style")).toBe("background: #ff0000");
    expect(tooltips[0].options.title).toBe("Shift<br><i>Desk</i>");
  });

  it("leaves an event without a description or colour plain", () => {
    const cal = boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: { title: "Shift", extendedProps: {} },
    });
    expect(el.getAttribute("style")).toBeNull();
    expect(tooltips[0].options.title).toBe("Shift");
  });
});
