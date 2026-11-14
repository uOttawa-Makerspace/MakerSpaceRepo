// @vitest-environment happy-dom
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  onTestFinished,
  vi,
} from "vitest";
import { Application } from "@hotwired/stimulus";

import { textsAttribute } from "../calendars/calendar_texts_fixture.js";

// A stand-in for FullCalendar that records its options and lets the test play
// the calendar's part: ask each source for a range, refetch one source.
const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.el = el;
      this.options = { weekends: true, ...options };
      this.view = {
        activeStart: new Date("2027-03-14T04:00:00Z"),
        activeEnd: new Date("2027-03-21T04:00:00Z"),
      };
      this.drawn = {};
      this.failed = {};
      created.push(this);
    }
    getOption(name) {
      return this.options[name];
    }
    setOption(name, value) {
      this.options[name] = value;
    }
    render() {
      this.rendered = true;
      this.el.innerHTML = Object.entries(this.options.customButtons)
        .map(
          ([name, { text }]) =>
            `<button class="fc-${name}-button">${text}</button>`,
        )
        .join("");
    }
    destroy() {
      this.destroyed = true;
    }
    source(id) {
      return this.options.eventSources.find((source) => source.id === id);
    }
    ask(id, info) {
      this.info = info;
      this.source(id).events(
        info,
        (rows) => (this.drawn[id] = rows),
        (error) => (this.failed[id] = error),
      );
    }
    askAll(info) {
      this.options.eventSources.forEach((source) => this.ask(source.id, info));
    }
    refetchEvents() {
      this.options.eventSources.forEach((source) =>
        this.ask(source.id, this.info),
      );
    }
    getEventSourceById(id) {
      return { refetch: () => this.ask(id, this.info) };
    }
  },
}));
vi.mock("@fullcalendar/rrule", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));

const tooltips = [];
vi.mock("bootstrap", () => ({
  Tooltip: class {
    constructor(el, options) {
      tooltips.push({ el, options });
    }
  },
}));

const closeSaved = vi.fn();
vi.mock("../../../app/javascript/src/calendar_dialog.js", () => ({
  closeSaved,
}));

const eventClick = vi.fn();
const eventCreate = vi.fn();
vi.mock("../../../app/javascript/src/calendar_helper.js", () => ({
  eventClick,
  eventCreate,
}));

const { default: CalendarSaved } =
  await import("../../../app/javascript/controllers/calendar_saved_controller.js");
const { default: AdminCalendar } =
  await import("../../../app/javascript/controllers/admin_calendar_controller.js");

const box = (target, id, value, action, { checked = true, color } = {}) =>
  `<input type="checkbox" id="${id}" value="${value}" ${checked ? "checked" : ""} ${color ? `data-color="${color}"` : ""} data-admin-calendar-target="${target}" data-action="admin-calendar#${action}">`;

function page({ hidden = {}, lang = "en" } = {}) {
  const shown = (param, value) => !(hidden[param] || []).includes(value);
  return `
<div data-controller="admin-calendar" data-admin-calendar-events-url-value="/admin/events/json/7" data-admin-calendar-unavailabilities-url-value="/admin/calendar/unavailabilities_json/7" data-admin-calendar-imported-url-value="/admin/calendar/imported_calendars_json/7">
  <section id="calendar_container" data-admin-calendar-target="container" style="display:none">
    ${box("allStaffEvents", "checkbox-all-events", "all-events", "toggleAllStaffEvents", { color: "#919191" })}
    ${box("allStaff", "checkbox-all", "all", "toggleAllStaff", { color: "#919191" })}
    ${[5, 6]
      .map(
        (id) => `<div>
      ${box("staffEvents", `checkbox-events-${id}`, id, "toggleStaffEvents", { checked: shown("hidden_staff_events", String(id)), color: "#f00" })}
      ${box("staff", `checkbox-${id}`, id, "toggleStaff", { checked: shown("hidden_staff", String(id)) })}
      <span data-user-id="${id}" data-admin-calendar-target="hours"></span></div>`,
      )
      .join("")}
    ${box("eventType", "checkbox-shift", "shift", "toggleEventType", { checked: shown("hidden_events", "shift") })}
    ${box("eventType", "checkbox-training", "training", "toggleEventType")}
    ${box("importedCalendar", "checkbox-cal1", "cal1", "toggleImportedCalendar")}
    <button id="publish" data-admin-calendar-target="publishDrafts"></button>
    <button id="delete" data-admin-calendar-target="deleteDrafts"></button>
    <input class="view_start_date" data-admin-calendar-target="viewStart"><input class="view_end_date" data-admin-calendar-target="viewEnd">
    <div id="calendar" data-admin-calendar-target="calendar" ${textsAttribute(lang)}><p id="stale">old</p></div>
  </section>
  <div id="spinner_container" data-admin-calendar-target="spinner"></div>
  <div id="eventModal" data-admin-calendar-target="dialog"></div>
</div>`;
}

const events = [
  {
    id: "shift",
    events: [
      {
        id: "event-1",
        title: "Opening",
        extendedProps: { eventType: "shift", assignedUsers: [{ id: 5 }] },
      },
      {
        id: "event-2",
        title: "Closing",
        extendedProps: {
          eventType: "shift",
          assignedUsers: [{ id: 5 }, { id: 6 }],
        },
      },
      {
        id: "event-3",
        title: "Orphan",
        extendedProps: { eventType: "shift", assignedUsers: [{ id: null }] },
      },
    ],
  },
  {
    id: "training",
    events: [
      {
        id: "event-4",
        title: "Training",
        rrule: "DTSTART:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO",
        extendedProps: {
          eventType: "training",
          assignedUsers: [{ id: 0, name: "Unassigned" }],
        },
      },
      {
        id: "event-5",
        title: "Broken",
        rrule: "not a rule",
        extendedProps: { eventType: "training", assignedUsers: [{ id: 0 }] },
      },
    ],
  },
];

const staff = [
  {
    id: 6,
    name: "Bob",
    color: "#0f0",
    unavailabilities: [
      {
        id: `11@${Date.UTC(2027, 2, 15, 14) / 1000}`,
        title: "🚫 Bob - Busy (Admin)",
        start: "2027-03-15T10:00:00-04:00",
        end: "2027-03-15T11:00:00-04:00",
        extendedProps: {
          name: "Bob",
          recordId: 11,
          eventType: "unavailability",
          isAdminCreated: true,
        },
      },
    ],
  },
  {
    id: 5,
    name: "Ann",
    color: "#f00",
    // an occurrence of Ann's external calendar: no record, not editable
    unavailabilities: [
      { id: "ext@1", title: "🚫 Ann - Away", extendedProps: { name: "Ann" } },
    ],
  },
];

const imported = [
  {
    id: "cal1",
    color: "#00f",
    events: [{ id: "a", groupId: "cal1", title: "Class" }],
  },
  {
    id: "cal2",
    color: "#0ff",
    events: [{ id: "b", groupId: "cal2", title: "Hours" }],
  },
];

let fetchMock;
function stubFetch({ ok = true } = {}) {
  fetchMock = vi.fn(async (url) => {
    const body = url.startsWith("/admin/events/json/")
      ? events
      : url.includes("unavailabilities_json")
        ? staff
        : imported;
    return {
      ok,
      status: ok ? 200 : 500,
      json: async () => structuredClone(body),
    };
  });
  vi.stubGlobal("fetch", fetchMock);
}

const WEEK = { startStr: "2027-03-14T00:00:00", endStr: "2027-03-21T00:00:00" };
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
const titles = (rows) => (rows || []).map((row) => row.title);
const $ = (id) => /** @type {HTMLInputElement} */ (document.getElementById(id));
let application;

async function boot({
  url = "http://localhost/admin/calendar",
  hidden,
  lang,
} = {}) {
  window.happyDOM.setURL(url);
  document.body.innerHTML = page({ hidden, lang });
  created.length = 0;
  application = Application.start();
  application.register("admin-calendar", AdminCalendar);
  application.register("calendar-saved", CalendarSaved);
  await settle();
  const calendar = created[0];
  calendar.askAll(WEEK);
  await settle();
  return calendar;
}

// Presses a toolbar button the calendar drew, as FullCalendar does: the
// handler is given the click and the button.
function press(calendar, name) {
  const button = calendar.el.querySelector(`.fc-${name}-button`);
  calendar.options.customButtons[name].click(new Event("click"), button);
}

async function click(id) {
  $(id).click();
  await settle();
}

beforeEach(() => {
  localStorage.clear();
  tooltips.length = 0;
  eventClick.mockClear();
  eventCreate.mockClear();
  window.scrollTo = vi.fn();
  vi.spyOn(console, "error").mockImplementation(() => {});
  globalThis.requestAnimationFrame = (fn) => fn();
  stubFetch();
});

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("a saved dialog", () => {
  it("closes the dialog and asks the events and unavailabilities again, not the imported calendars", async () => {
    const calendar = await boot();
    fetchMock.mockClear();
    events[0].events[0].title = "Opening (renamed)";
    onTestFinished(() => (events[0].events[0].title = "Opening"));

    document.body.insertAdjacentHTML(
      "beforeend",
      `<span data-controller="calendar-saved" data-calendar-saved-admin-calendar-outlet="[data-controller~=admin-calendar]"></span>`,
    );
    await settle();

    expect(closeSaved).toHaveBeenCalledWith($("eventModal"));
    expect(fetchMock.mock.calls.map(([url]) => url.split("?")[0])).toEqual([
      "/admin/events/json/7",
      "/admin/calendar/unavailabilities_json/7",
    ]);
    expect(titles(calendar.drawn.events)).toContain("Opening (renamed)");
  });
});

describe("loading the calendar", () => {
  it("draws on an empty calendar element, shows it and hides the spinner", async () => {
    const calendar = await boot();

    expect(calendar.rendered).toBe(true);
    expect(document.getElementById("stale")).toBeNull();
    expect($("calendar_container").style.display).toBe("block");
    expect($("spinner_container").style.display).toBe("none");
    expect(window.scrollTo).toHaveBeenCalled();
  });

  it("asks each feed for the range shown", async () => {
    await boot();

    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "/admin/events/json/7?start=2027-03-14T00%3A00%3A00&end=2027-03-21T00%3A00%3A00",
      "/admin/calendar/unavailabilities_json/7?start=2027-03-14T00%3A00%3A00&end=2027-03-21T00%3A00%3A00",
      "/admin/calendar/imported_calendars_json/7?start=2027-03-14T00%3A00%3A00&end=2027-03-21T00%3A00%3A00",
    ]);
  });

  it("asks again for a new range, and not for the same range", async () => {
    const calendar = await boot();
    calendar.ask("events", WEEK);
    await settle();
    expect(fetchMock).toHaveBeenCalledTimes(3);

    calendar.ask("events", {
      startStr: "2027-03-21T00:00:00",
      endStr: "2027-03-28T00:00:00",
    });
    await settle();
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  it("tells the calendar when a feed fails", async () => {
    stubFetch({ ok: false });
    const calendar = await boot();

    expect(calendar.failed.events.message).toBe(
      "/admin/events/json/7 answered 500",
    );
    expect(calendar.drawn.events).toBeUndefined();
  });

  it("asks again after a failed request when a filter redraws the same range", async () => {
    stubFetch({ ok: false });
    const calendar = await boot();
    stubFetch();
    await click("checkbox-cal1");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(titles(calendar.drawn.imported)).toEqual(["Hours"]);
  });

  it("paints the filter boxes in their colours", async () => {
    await boot();

    expect($("checkbox-events-5").style.backgroundColor).toBe("#f00");
    expect($("checkbox-all").style.borderColor).toBe("#919191");
    expect($("checkbox-shift").style.backgroundColor).toBe("");
  });

  it("removes the calendar when the element leaves the page", async () => {
    const calendar = await boot();
    document.body.innerHTML = "";
    await settle();

    expect(calendar.destroyed).toBe(true);
  });
});

describe("the rows drawn", () => {
  it("draws every event, reading each rule the way rrule.js writes it, and keeping one it cannot read", async () => {
    const calendar = await boot();

    expect(titles(calendar.drawn.events)).toEqual([
      "Opening",
      "Closing",
      "Orphan",
      "Training",
      "Broken",
    ]);
    const [training, broken] = calendar.drawn.events.slice(3);
    expect(training.rrule).toBe(
      "DTSTART:20270301T100000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO",
    );
    expect(broken.rrule).toBe("not a rule");
    expect(console.error).toHaveBeenCalled();
  });

  it("draws each unavailability occurrence as sent, in its staff member's colour, an external one not editable", async () => {
    const calendar = await boot();
    const [busy, away] = calendar.drawn.unavailabilities;

    expect(busy).toMatchObject({
      color: "#0f0",
      start: "2027-03-15T10:00:00-04:00",
      end: "2027-03-15T11:00:00-04:00",
      extendedProps: {
        name: "Bob",
        recordId: 11,
        eventType: "unavailability",
        userId: 6,
        isAdminCreated: true,
      },
    });
    expect(away).toMatchObject({ color: "#f00", extendedProps: { userId: 5 } });
    expect(away.extendedProps).not.toHaveProperty("eventType");
  });

  it("draws each imported event in its calendar's colour", async () => {
    const calendar = await boot();

    expect(calendar.drawn.imported.map((row) => row.color)).toEqual([
      "#00f",
      "#0ff",
    ]);
  });
});

describe("filters", () => {
  it("starts from the boxes the page ticked", async () => {
    const calendar = await boot({
      hidden: { hidden_events: ["shift"], hidden_staff: ["6"] },
    });

    expect(titles(calendar.drawn.events)).toEqual(["Training", "Broken"]);
    expect(titles(calendar.drawn.unavailabilities)).toEqual(["🚫 Ann - Away"]);
  });

  it("hides and shows an event type without asking the feed again, and records it in the address", async () => {
    const calendar = await boot();
    await click("checkbox-training");

    expect(titles(calendar.drawn.events)).toEqual([
      "Opening",
      "Closing",
      "Orphan",
    ]);
    expect(
      new URL(window.location.href).searchParams.get("hidden_events"),
    ).toBe("training");
    expect(fetchMock).toHaveBeenCalledTimes(3);

    await click("checkbox-training");
    expect(titles(calendar.drawn.events)).toHaveLength(5);
    expect(window.location.search).toBe("");
  });

  it("keeps several hidden types in one comma separated parameter", async () => {
    await boot();
    await click("checkbox-shift");
    await click("checkbox-training");

    expect(
      new URL(window.location.href).searchParams.get("hidden_events"),
    ).toBe("shift,training");
  });

  it("hides an event only when every staff member assigned to it is hidden", async () => {
    const calendar = await boot();
    await click("checkbox-events-5");

    expect(titles(calendar.drawn.events)).toEqual([
      "Closing",
      "Orphan",
      "Training",
      "Broken",
    ]);
    expect($("checkbox-all-events").checked).toBe(false);
    expect(window.location.search).toBe("?hidden_staff_events=5");

    await click("checkbox-events-6");
    expect(titles(calendar.drawn.events)).toEqual([
      "Orphan",
      "Training",
      "Broken",
    ]);
  });

  it("ticks and unticks every staff events box with the all events box", async () => {
    const calendar = await boot();
    await click("checkbox-all-events");

    expect($("checkbox-events-5").checked).toBe(false);
    expect($("checkbox-events-6").checked).toBe(false);
    expect(window.location.search).toBe("?hidden_staff_events=5%2C6");
    expect(titles(calendar.drawn.events)).toEqual([
      "Orphan",
      "Training",
      "Broken",
    ]);

    await click("checkbox-all-events");
    expect($("checkbox-events-5").checked).toBe(true);
    expect(window.location.search).toBe("");
  });

  it("hides one staff member's unavailabilities and unticks All Staff", async () => {
    const calendar = await boot();
    await click("checkbox-6");

    expect(titles(calendar.drawn.unavailabilities)).toEqual(["🚫 Ann - Away"]);
    expect($("checkbox-all").checked).toBe(false);
    expect(window.location.search).toBe("?hidden_staff=6");

    await click("checkbox-6");
    expect(titles(calendar.drawn.unavailabilities)).toHaveLength(2);
    expect($("checkbox-all").checked).toBe(false);
  });

  it("ticks and unticks every staff box with All Staff", async () => {
    const calendar = await boot();
    await click("checkbox-all");

    expect($("checkbox-5").checked).toBe(false);
    expect(titles(calendar.drawn.unavailabilities)).toEqual([]);
    expect(window.location.search).toBe("?hidden_staff=5%2C6");

    await click("checkbox-all");
    expect(titles(calendar.drawn.unavailabilities)).toHaveLength(2);
  });

  it("hides and shows an imported calendar", async () => {
    const calendar = await boot();
    await click("checkbox-cal1");

    expect(titles(calendar.drawn.imported)).toEqual(["Hours"]);
    expect(window.location.search).toBe("?hidden_calendars=cal1");
  });

  it("drops hidden ids the page no longer lists and keeps other parameters", async () => {
    await boot({
      url: "http://localhost/admin/calendar?hidden_staff=99&view=x",
    });
    await click("checkbox-shift");

    expect(window.location.search).toBe("?view=x&hidden_events=shift");
  });
});

describe("calendar options", () => {
  it("opens the event modal for a clicked event and a selected range", async () => {
    const calendar = await boot();
    calendar.options.eventClick({ event: { id: "x" } });
    calendar.options.select({ startStr: "a" });

    expect(eventClick).toHaveBeenCalledWith({ id: "x" });
    expect(eventCreate).toHaveBeenCalledWith({ startStr: "a" });
  });

  it("labels the toolbar buttons, then toggles weekends and relabels", async () => {
    const calendar = await boot();
    const weekends = calendar.el.querySelector(".fc-toggleWeekends-button");
    expect(weekends.textContent).toBe("Hide Weekends");

    press(calendar, "toggleWeekends");
    expect(calendar.options.weekends).toBe(false);
    expect(weekends.textContent).toBe("Show Weekends");
  });

  it("toggles event overlap, remembers it and relabels the button", async () => {
    const calendar = await boot();
    const overlap = calendar.el.querySelector(".fc-toggleEventOverlap-button");
    expect(overlap.textContent).toBe("Enable Event Overlap");

    press(calendar, "toggleEventOverlap");
    expect(calendar.options.slotEventOverlap).toBe(true);
    expect(localStorage.fullCalendarEventOverlap).toBe("true");
    expect(overlap.textContent).toBe("Disable Event Overlap");
  });

  it("names its buttons, drafts and hours in French on a French page", async () => {
    localStorage.fullCalendarEventOverlap = "true";
    const calendar = await boot({ lang: "fr" });
    const label = (name) =>
      calendar.el.querySelector(`.fc-${name}-button`).textContent;
    expect(label("toggleWeekends")).toBe("Masquer les fins de semaine");
    expect(label("toggleEventOverlap")).toBe(
      "Désactiver le chevauchement des événements",
    );

    press(calendar, "toggleWeekends");
    press(calendar, "toggleEventOverlap");
    expect(label("toggleWeekends")).toBe("Afficher les fins de semaine");
    expect(label("toggleEventOverlap")).toBe(
      "Activer le chevauchement des événements",
    );

    const view = (type) => ({ type, currentStart: new Date() });
    calendar.options.datesSet({ view: view("timeGridWeek") });
    expect($("publish").innerText).toBe(
      "Publier les brouillons de cette semaine",
    );
    calendar.options.datesSet({ view: view("dayGridMonth") });
    expect($("delete").innerText).toBe(
      "Supprimer les brouillons de ce mois-ci",
    );

    calendar.options.eventsSet([]);
    expect(document.querySelector("[data-user-id]").textContent).toBe("0 h");
  });

  it("starts with overlap on and the remembered date", async () => {
    localStorage.fullCalendarEventOverlap = "true";
    localStorage.fullCalendarDefaultDateAdmin = "2027-03-16T12:00:00.000Z";
    const calendar = await boot();

    expect(calendar.options.slotEventOverlap).toBe(true);
    expect(calendar.options.initialDate).toBe("2027-03-16T12:00:00.000Z");
  });

  it("decorates a mounted event, its title and description as text", async () => {
    const calendar = await boot();
    const el = document.createElement("div");
    calendar.options.eventDidMount({
      el,
      event: {
        title: "<b>Shift</b>",
        extendedProps: {
          description: "<img src=x>",
          background: "#123456",
          isAdminCreated: true,
        },
      },
    });

    expect(el.classList.contains("fade-in")).toBe(true);
    expect(el.classList.contains("admin-created-unavailability")).toBe(true);
    expect(el.getAttribute("style")).toBe("background: #123456");
    expect(tooltips[0].options.title).toBe(
      "&lt;b&gt;Shift&lt;/b&gt;<br><i>&lt;img src=x&gt;</i>",
    );
  });

  it("leaves a plain event undecorated", async () => {
    const calendar = await boot();
    const el = document.createElement("div");
    calendar.options.eventDidMount({
      el,
      event: { title: "Plain", extendedProps: {} },
    });

    expect(el.classList.contains("admin-created-unavailability")).toBe(false);
    expect(el.getAttribute("style")).toBeNull();
    expect(tooltips[0].options.title).toBe("Plain");
  });

  it("remembers the date, fills the range fields and names the draft buttons for the view", async () => {
    const calendar = await boot();
    calendar.options.datesSet({
      startStr: "2027-03-14T00:00:00",
      endStr: "2027-03-21T00:00:00",
      view: {
        type: "timeGridWeek",
        currentStart: new Date("2027-03-14T04:00:00Z"),
      },
    });

    expect(localStorage.fullCalendarDefaultDateAdmin).toBe(
      "2027-03-14T04:00:00.000Z",
    );
    expect(document.querySelector(".view_start_date").value).toBe(
      "2027-03-14T00:00:00",
    );
    expect(document.querySelector(".view_end_date").value).toBe(
      "2027-03-21T00:00:00",
    );
    expect($("publish").innerText).toBe("Publish This Week's Drafts");

    calendar.options.datesSet({
      startStr: "a",
      endStr: "b",
      view: { type: "dayGridMonth", currentStart: new Date() },
    });
    expect($("delete").innerText).toBe("Delete This Month's Drafts");
  });

  it("shows each staff member's hours in the events shown within the view", async () => {
    const calendar = await boot();
    const at = (iso) => new Date(iso);
    calendar.options.eventsSet([
      {
        start: at("2027-03-15T13:00:00Z"),
        end: at("2027-03-15T16:00:00Z"),
        extendedProps: { assignedUsers: [{ id: 5 }, { id: 6 }] },
      },
      {
        start: at("2027-03-16T13:00:00Z"),
        end: at("2027-03-16T14:30:00Z"),
        extendedProps: { assignedUsers: [{ id: 5 }] },
      },
      {
        start: at("2027-03-21T13:00:00Z"),
        end: at("2027-03-21T14:00:00Z"),
        extendedProps: { assignedUsers: [{ id: 5 }] },
      },
      {
        start: at("2027-03-15T13:00:00Z"),
        end: at("2027-03-15T14:00:00Z"),
        extendedProps: {},
      },
    ]);

    const hours = [...document.querySelectorAll("[data-user-id]")].map(
      (badge) => badge.textContent,
    );
    expect(hours).toEqual(["4.5 hrs", "3 hrs"]);
  });
});
