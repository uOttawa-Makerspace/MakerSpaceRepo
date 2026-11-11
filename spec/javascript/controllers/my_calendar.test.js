// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.options = { slotEventOverlap: false, ...options };
      this.eventList = [];
      this.rendered = false;
      this.destroyed = false;
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
    destroy() {
      this.destroyed = true;
    }
  },
}));
vi.mock("@fullcalendar/rrule", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));

const tooltips = [];
const disposed = [];
vi.mock("bootstrap", () => ({
  Tooltip: class {
    constructor(el, options) {
      tooltips.push({ el, options });
    }
    static getInstance(el) {
      return el.dataset.tip ? { dispose: () => disposed.push(el) } : null;
    }
  },
}));

const PAGE = `
<div data-controller="my-calendar" data-my-calendar-feed-url-value="/staff/my_calendar/json/3">
  <div id="calendar_container" data-my-calendar-target="container" style="display:none">
    <div id="calendar" data-my-calendar-target="calendar"><p id="stale">old</p></div>
  </div>
  <div id="spinner_container" data-my-calendar-target="spinner"></div>
  <span class="fc-toggleOthersShifts-button"></span>
  <span class="fc-toggleEventOverlap-button"></span>
</div>
<span class="fc-toggleOthersShifts-button" id="foreign"></span>`;

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function boot() {
  document.body.innerHTML = PAGE;
  created.length = 0;
  application = Application.start();
  application.register("my-calendar", MyCalendar);
  await settle();
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

const { default: MyCalendar } =
  await import("../../../app/javascript/controllers/my_calendar_controller.js");

let application;

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
});

beforeEach(() => {
  localStorage.clear();
  tooltips.length = 0;
  disposed.length = 0;
  globalThis.requestAnimationFrame = (fn) => fn();
});

describe("my calendar", () => {
  it("does nothing without the controller element", async () => {
    document.body.innerHTML = '<div id="calendar"></div>';
    created.length = 0;
    application = Application.start();
    application.register("my-calendar", MyCalendar);
    await settle();
    document.dispatchEvent(new Event("turbo:load"));
    expect(created).toHaveLength(0);
  });

  it("draws once on its own calendar and clears markup left by a cached page", async () => {
    const cal = await boot();
    expect(created).toHaveLength(1);
    expect(document.getElementById("stale")).toBeNull();
    document.dispatchEvent(new Event("turbo:load"));
    expect(created).toHaveLength(1);
    expect(cal.destroyed).toBe(false);
  });

  it("destroys the calendar when the element leaves the page", async () => {
    const cal = await boot();
    document.body.innerHTML = "";
    await settle();
    expect(cal.destroyed).toBe(true);
  });

  it("disposes an event's tooltip when the event is removed", async () => {
    const cal = await boot();
    const el = document.createElement("div");
    el.dataset.tip = "1";
    cal.options.eventWillUnmount({ el });
    expect(disposed).toEqual([el]);
    cal.options.eventWillUnmount({ el: document.createElement("div") });
    expect(disposed).toHaveLength(1);
  });

  it("reads the events of the space and shows the calendar", async () => {
    const cal = await boot();
    expect(cal.options.events).toBe("/staff/my_calendar/json/3");
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

  it("starts at the remembered date and overlap setting", async () => {
    localStorage.fullCalendarEventOverlap = "true";
    localStorage.fullCalendarDefaultDateStaffCalendar = "2026-03-02T00:00:00Z";
    const cal = await boot();
    expect(cal.options.slotEventOverlap).toBe(true);
    expect(cal.options.initialDate).toBe("2026-03-02T00:00:00Z");
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Disable Event Overlap");
  });

  it("remembers the first day of the view", async () => {
    const cal = await boot();
    cal.options.datesSet({
      view: { currentStart: new Date("2026-11-02T00:00:00Z") },
    });
    expect(localStorage.fullCalendarDefaultDateStaffCalendar).toBe(
      "2026-11-02T00:00:00.000Z",
    );
  });

  it("toggles event overlap, remembers it and relabels the button", async () => {
    const cal = await boot();
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

  it("hides other people's shifts, then shows them all again", async () => {
    const cal = await boot();
    const mine = shift("a", true);
    const theirs = shift("b", false);
    cal.eventList = [mine, theirs];

    cal.options.customButtons.toggleOthersShifts.click();
    expect(mine.props.display).toBe("auto");
    expect(theirs.props.display).toBe("none");
    expect(
      document.querySelector(".fc-toggleOthersShifts-button").innerHTML,
    ).toBe("Show All Shifts");
    expect(document.getElementById("foreign").innerHTML).toBe("");

    cal.options.customButtons.toggleOthersShifts.click();
    expect(theirs.props.display).toBe("auto");
    expect(
      document.querySelector(".fc-toggleOthersShifts-button").innerHTML,
    ).toBe("Show My Shifts Only");
  });

  it("decorates a mounted event with a tooltip, fade in and user colour", async () => {
    const cal = await boot();
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
    expect(tooltips[0].options.title.innerHTML).toBe("Shift<br><i>Desk</i>");
  });

  it("leaves an event without a description or colour plain", async () => {
    const cal = await boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: { title: "Shift", extendedProps: {} },
    });
    expect(el.getAttribute("style")).toBeNull();
    expect(tooltips[0].options.title.innerHTML).toBe("Shift");
  });

  it("shows markup in a title or description as text", async () => {
    const cal = await boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: {
        title: "<img src=x onerror=alert(1)>",
        extendedProps: { description: "<b>bold</b>" },
      },
    });
    const content = tooltips[0].options.title;
    expect(content.querySelector("img, b")).toBeNull();
    expect(content.textContent).toBe("<img src=x onerror=alert(1)><b>bold</b>");
    expect(content.querySelector("i").textContent).toBe("<b>bold</b>");
  });
});
