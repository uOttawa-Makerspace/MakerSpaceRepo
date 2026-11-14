// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

import { textsAttribute } from "../calendars/calendar_texts_fixture.js";

// A stand-in for FullCalendar that records its options and lets the test play
// the calendar's part: ask the source for a range, refetch it, resize.
const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      this.view = { type: options.initialView };
      this.changedTo = null;
      created.push(this);
    }
    render() {
      this.rendered = true;
      this.el.innerHTML = '<div class="fc-view"></div>';
    }
    destroy() {
      this.destroyed = true;
    }
    ask(info) {
      this.info = info;
      this.options.eventSources[0].events(
        info,
        (rows) => (this.drawn = rows),
        (error) => (this.failed = error),
      );
    }
    getEventSourceById(id) {
      return id === "hours" ? { refetch: () => this.ask(this.info) } : null;
    }
    changeView(type) {
      this.changedTo = type;
      this.view.type = type;
    }
  },
}));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));

const { default: HoursCalendar } =
  await import("../../../app/javascript/controllers/hours_calendar_controller.js");

const filter = (id, color) =>
  `<input type="checkbox" id="filter-${id}" value="${id}" data-color="${color}" checked data-hours-calendar-target="filter" data-action="hours-calendar#redraw">`;

function page({
  week = false,
  lang = "en",
  filters = [filter("a", "#112233"), filter("b", "#445566")],
} = {}) {
  return `
<div data-controller="hours-calendar" data-hours-calendar-feed-url-value="/open_hours" ${week ? 'data-hours-calendar-week-value="true"' : ""}>
  <div id="calendar" data-hours-calendar-target="calendar" ${textsAttribute(lang)}><p id="stale">old</p></div>
  <div id="filters">${filters.join("")}</div>
</div>`;
}

const week = { startStr: "2027-03-14T00:00:00", endStr: "2027-03-21T00:00:00" };
const feed = [
  {
    id: "a",
    color: "#112233",
    events: [{ id: "a1", groupId: "a", title: "Open" }],
  },
  {
    id: "b",
    color: "#445566",
    events: [{ id: "b1", groupId: "b", title: "Lab" }],
  },
];

let application;
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(options) {
  window.innerWidth = options?.width ?? 1200;
  document.body.innerHTML = page(options);
  application = Application.start();
  application.register("hours-calendar", HoursCalendar);
  await tick();
  return created.at(-1);
}

function answer(body, ok = true) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok, status: ok ? 200 : 500, json: async () => body })),
  );
}

beforeEach(() => {
  created.length = 0;
  answer(feed);
});

afterEach(() => {
  application?.stop();
  vi.unstubAllGlobals();
});

describe("hours calendar", () => {
  it("draws one calendar in place of what a cached page held, with the filters coloured", async () => {
    const calendar = await mount();
    expect(created).toHaveLength(1);
    expect(calendar.rendered).toBe(true);
    expect(document.getElementById("stale")).toBeNull();
    const box = /** @type {HTMLInputElement} */ (
      document.getElementById("filter-a")
    );
    expect(box.style.backgroundColor).not.toBe("");
    expect(box.style.borderColor).not.toBe("");
    expect(calendar.options.plugins).toHaveLength(2);
    expect(calendar.options.timeZone).toBe("America/Toronto");
  });

  it("names its previous and next buttons after the days it steps by, in the page's language", async () => {
    expect((await mount()).options.buttonHints).toEqual({
      prev: "Previous days",
      next: "Next days",
    });
    application.stop();
    expect((await mount({ lang: "fr" })).options.buttonHints).toEqual({
      prev: "Jours précédents",
      next: "Jours suivants",
    });
  });

  it("draws nothing when the server lists no calendar, leaving its message", async () => {
    window.innerWidth = 1200;
    document.body.innerHTML = page({ filters: [] }).replace(
      '<p id="stale">old</p>',
      "<p>No open hours available</p>",
    );
    application = Application.start();
    application.register("hours-calendar", HoursCalendar);
    await tick();
    expect(created).toHaveLength(0);
    expect(document.getElementById("calendar").textContent).toBe(
      "No open hours available",
    );
  });

  it("asks the feed for the range shown and draws each row in its calendar's colour", async () => {
    const calendar = await mount();
    calendar.ask(week);
    await tick();
    expect(fetch).toHaveBeenCalledWith(
      "/open_hours?start=2027-03-14T00%3A00%3A00&end=2027-03-21T00%3A00%3A00",
      { headers: { Accept: "application/json" } },
    );
    expect(calendar.drawn).toEqual([
      { id: "a1", groupId: "a", title: "Open", color: "#112233" },
      { id: "b1", groupId: "b", title: "Lab", color: "#445566" },
    ]);
  });

  it("hides a calendar's hours when its box is cleared, without asking again", async () => {
    const calendar = await mount();
    calendar.ask(week);
    await tick();
    const box = /** @type {HTMLInputElement} */ (
      document.getElementById("filter-a")
    );
    box.checked = false;
    box.dispatchEvent(new Event("input", { bubbles: true }));
    await tick();
    expect(calendar.drawn.map((row) => row.id)).toEqual(["b1"]);

    box.checked = true;
    box.dispatchEvent(new Event("input", { bubbles: true }));
    await tick();
    expect(calendar.drawn.map((row) => row.id)).toEqual(["a1", "b1"]);
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("asks again for a new range", async () => {
    const calendar = await mount();
    calendar.ask(week);
    calendar.ask({
      startStr: "2027-03-21T00:00:00",
      endStr: "2027-03-28T00:00:00",
    });
    await tick();
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reports a failed request to the calendar and asks again on the next redraw", async () => {
    answer([], false);
    const calendar = await mount();
    calendar.ask(week);
    await tick();
    expect(calendar.failed).toEqual(new Error("/open_hours answered 500"));

    answer(feed);
    calendar.getEventSourceById("hours").refetch();
    await tick();
    expect(calendar.drawn).toHaveLength(2);
  });

  it.each([
    [1200, false, "timeGridFiveDay"],
    [500, false, "timeGridTwoDay"],
    [1200, true, "timeGridSevenDay"],
    [500, true, "timeGridThreeDay"],
  ])(
    "at width %i (hours page %s) starts in the %s view",
    async (width, onHoursPage, view) => {
      const calendar = await mount({ width, week: onHoursPage });
      expect(calendar.options.initialView).toBe(view);
      expect(calendar.options.allDaySlot).toBe(onHoursPage);
    },
  );

  it("switches view when the window crosses the narrow width, and only then", async () => {
    const calendar = await mount();
    window.innerWidth = 500;
    calendar.options.windowResize();
    expect(calendar.changedTo).toBe("timeGridTwoDay");

    calendar.changedTo = null;
    calendar.options.windowResize();
    expect(calendar.changedTo).toBeNull();
  });

  it("removes the calendar when the element leaves the page", async () => {
    const calendar = await mount();
    document.body.innerHTML = "";
    await tick();
    expect(calendar.destroyed).toBe(true);
  });
});
