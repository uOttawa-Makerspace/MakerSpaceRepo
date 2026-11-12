// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

// A stand-in for FullCalendar that records its options and event sources, so
// the page script's own logic can be driven without a real calendar.
const created = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.el = el;
      this.options = { slotEventOverlap: false, weekends: true, ...options };
      this.sources = new Map();
      this.refetched = 0;
      this.rendered = false;
      this.eventList = [];
      this.view = {
        activeStart: new Date("2026-11-01T00:00:00Z"),
        activeEnd: new Date("2026-11-08T00:00:00Z"),
      };
      created.push(this);
    }
    getOption(name) {
      return this.options[name];
    }
    setOption(name, value) {
      this.options[name] = value;
    }
    addEventSource(source) {
      this.sources.set(String(source.id), source);
    }
    getEventSourceById(id) {
      const key = String(id);
      if (!this.sources.has(key)) return null;
      return {
        remove: () => this.sources.delete(key),
        refetch: () => this.refetched++,
      };
    }
    refetchEvents() {
      this.refetched++;
    }
    getEvents() {
      return this.eventList;
    }
    render() {
      this.rendered = true;
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

const eventClick = vi.fn();
const eventCreate = vi.fn();
vi.mock("../../../app/javascript/src/calendar_helper.js", () => ({
  eventClick,
  eventCreate,
}));

const PAGE = `
<div id="space_id" value="7"></div>
<button id="publish_drafts_button"></button>
<button id="delete_drafts_button"></button>
<input class="view_start_date"><input class="view_end_date">
<div id="calendar_container" style="display:none"></div>
<div id="spinner_container"></div>
<div id="calendar"></div>
<span class="fc-toggleWeekends-button"></span>
<span class="fc-toggleEventOverlap-button"></span>
<h6></h6><div id="events_checkbox_container"></div>
<h6></h6><div id="staff_checkbox_container"></div>
<h6></h6><div id="calendars_checkbox_container"></div>
<span id="imported_calendars_status"></span>`;

const eventGroups = [
  {
    id: "shift",
    color: "#111",
    events: [
      {
        id: "1",
        title: "Opening",
        extendedProps: {
          name: "Shifts",
          assignedUsers: [{ id: 5 }],
        },
      },
      {
        id: "2",
        title: "Closing",
        extendedProps: { name: "Shifts", assignedUsers: [{ id: 6 }] },
      },
    ],
  },
  {
    id: "training",
    color: "#222",
    events: [
      {
        id: "3",
        title: "Training",
        rrule: "DTSTART:20261101T100000Z\nRRULE:FREQ=DAILY;COUNT=2",
        extendedProps: { name: "Trainings", assignedUsers: [{ id: 0 }] },
      },
      {
        id: "4",
        title: "Broken",
        rrule: "not an rrule",
        extendedProps: { name: "Trainings", assignedUsers: [{ id: 0 }] },
      },
    ],
  },
];

const staff = [
  {
    id: 5,
    name: "Ann",
    color: "#f00",
    unavailabilities: [
      {
        id: "u1",
        title: "Busy (Admin)",
        rrule: "DTSTART:20261101T100000Z\nRRULE:FREQ=WEEKLY;COUNT=2",
        extendedProps: { name: "Ann" },
        textColor: "#fff",
      },
      { id: "u2", title: "Away", rrule: "garbage", extendedProps: {} },
    ],
  },
  { id: 6, name: "Bob", color: "#0f0", unavailabilities: [] },
];

const calendars = [
  {
    id: "cal1",
    color: "#00f",
    events: [{ extendedProps: { name: "Imported" }, textColor: "#abc" }],
  },
];

function stubFetch({ events = eventGroups, unavail = staff, imported = [] }) {
  const fetchMock = vi.fn(async (url) => {
    const body = url.includes("/admin/events/json/")
      ? events
      : url.includes("unavailabilities_json")
        ? unavail
        : imported;
    return { json: async () => structuredClone(body) };
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

async function boot({
  url = "http://localhost/admin/calendar",
  page = PAGE,
} = {}) {
  window.happyDOM.setURL(url);
  document.body.innerHTML = page;
  document.getElementById("space_id").value = "7";
  created.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
  // the handler is async and awaits three fetches
  await vi.waitFor(() => expect(created[0]?.sources.size).toBeGreaterThan(0));
  await vi.waitFor(() =>
    expect(
      document.getElementById("imported_calendars_status").innerText,
    ).not.toBe(undefined),
  );
  await new Promise((r) => setTimeout(r, 0));
  return created[0];
}

await import("../../../app/javascript/src/fullcalendar_setup_admin.js");

beforeEach(() => {
  localStorage.clear();
  tooltips.length = 0;
  eventClick.mockClear();
  eventCreate.mockClear();
  window.scrollTo = vi.fn();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(console, "log").mockImplementation(() => {});
  globalThis.requestAnimationFrame = (fn) => fn();
});

describe("page without the calendar", () => {
  it("does nothing", () => {
    document.body.innerHTML = "<p>elsewhere</p>";
    created.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(created).toEqual([]);
  });
});

describe("loading the calendar", () => {
  it("fetches the three sources for the space and renders", async () => {
    const fetchMock = stubFetch({ imported: calendars });
    const cal = await boot();

    expect(fetchMock.mock.calls.map((c) => c[0])).toEqual([
      "/admin/events/json/7",
      "/admin/calendar/unavailabilities_json/7",
      "/admin/calendar/imported_calendars_json/7",
    ]);
    expect(cal.rendered).toBe(true);
    expect(document.getElementById("calendar_container").style.display).toBe(
      "block",
    );
    expect(document.getElementById("spinner_container").style.display).toBe(
      "none",
    );
    expect(window.scrollTo).toHaveBeenCalled();
    expect(document.querySelector(".fc-toggleWeekends-button").innerHTML).toBe(
      "Hide Weekends",
    );
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Enable Event Overlap");
  });

  it("stops when the space id is missing", async () => {
    stubFetch({});
    document.body.innerHTML = '<div id="calendar"></div>';
    created.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    await vi.waitFor(() =>
      expect(console.error).toHaveBeenCalledWith("space_id element not found"),
    );
    expect(created[0].rendered).toBe(false);
  });

  it("quietly makes no request when the space picker has no value", async () => {
    const fetchMock = stubFetch({});
    document.body.innerHTML = PAGE;
    document.getElementById("space_id").value = "";
    created.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(console.error).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(created[0].rendered).toBe(false);
  });

  it("keeps the shifts of an assignment whose user was deleted", async () => {
    const orphaned = [
      {
        id: "shift",
        color: "#111",
        events: [
          {
            id: "9",
            title: "Orphan",
            extendedProps: { name: "Shifts", assignedUsers: [{ id: null }] },
          },
        ],
      },
    ];
    stubFetch({ events: orphaned });
    const cal = await boot();
    let out;
    cal.sources.get("staffEvents").events({}, (list) => (out = list));
    expect(out.map((e) => e.id)).toEqual(["9"]);
  });

  it("lists one checkbox per event type and one per staff member", async () => {
    stubFetch({ imported: calendars });
    await boot();

    const types = [
      ...document.querySelectorAll("#events_checkbox_container label"),
    ].map((l) => l.textContent);
    expect(types).toEqual(["Shifts", "Trainings"]);

    const staffLabels = [
      ...document.querySelectorAll("#staff_checkbox_container label"),
    ].map((l) => l.textContent);
    expect(staffLabels).toEqual(
      expect.arrayContaining(["All Staff", "Ann", "Bob (0 unavailabilities)"]),
    );

    expect(
      document.querySelector("#calendars_checkbox_container label").textContent,
    ).toBe("Imported");
    expect(
      document.getElementById("imported_calendars_status").style.display,
    ).toBe("none");
  });

  it("says when there are no imported calendars", async () => {
    stubFetch({ imported: [] });
    await boot();
    expect(document.getElementById("imported_calendars_status").innerText).toBe(
      "No calendars found",
    );
  });

  it("names a checkbox 'Unnamed Calendar' when its source has no events", async () => {
    stubFetch({ imported: [{ id: "bare", color: "#000", events: [] }] });
    await boot();
    expect(
      document.querySelector("#calendars_checkbox_container label").textContent,
    ).toBe("Unnamed Calendar");
  });

  it("marks admin-created unavailabilities and tolerates a bad rule", async () => {
    stubFetch({});
    const cal = await boot();
    const events = cal.sources.get("5").events;
    expect(events[0].extendedProps).toMatchObject({
      eventType: "unavailability",
      userId: 5,
      isAdminCreated: true,
    });
    expect(events[0].rrule).toContain("FREQ=WEEKLY");
    expect(events[1].extendedProps.isAdminCreated).toBe(false);
    expect(console.error).toHaveBeenCalled();

    const placeholder = cal.sources.get("6").events[0];
    expect(placeholder.id).toBe("no-unavailabilties");
  });
});

describe("event type filter", () => {
  const shown = (cal) => {
    let out;
    cal.sources
      .get("staffEvents")
      .events({}, (list) => (out = list.map((e) => e.id)));
    return out;
  };

  it("shows every type by default", async () => {
    stubFetch({});
    const cal = await boot();
    expect(shown(cal)).toEqual(["1", "2", "3", "4"]);
  });

  it("starts with the types hidden by the address unchecked", async () => {
    stubFetch({});
    const cal = await boot({
      url: "http://localhost/admin/calendar?hidden_events=training",
    });
    expect(shown(cal)).toEqual(["1", "2"]);
    const box = document.getElementById("checkbox-training");
    expect(box.checked).toBe(false);
  });

  it("hides and shows a type from its checkbox and records it in the address", async () => {
    stubFetch({});
    const cal = await boot();
    const box = document.getElementById("checkbox-shift");

    box.checked = false;
    box.dispatchEvent(new Event("change"));
    expect(shown(cal)).toEqual(["3", "4"]);
    expect(window.location.search).toContain("hidden_events=shift");
    expect(cal.refetched).toBe(1);

    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(shown(cal)).toEqual(["1", "2", "3", "4"]);
    expect(window.location.search).not.toContain("hidden_events");
  });

  it("keeps several hidden types in one comma separated parameter", async () => {
    stubFetch({});
    await boot();
    for (const id of ["shift", "training"]) {
      const box = document.getElementById(`checkbox-${id}`);
      box.checked = false;
      box.dispatchEvent(new Event("change"));
    }
    expect(
      new URLSearchParams(window.location.search).get("hidden_events"),
    ).toBe("shift,training");
  });
});

describe("staff filters", () => {
  const shownEvents = (cal) => {
    let out;
    cal.sources
      .get("staffEvents")
      .events({}, (list) => (out = list.map((e) => e.id)));
    return out;
  };

  it("hides the shifts of a staff member from the events checkbox", async () => {
    stubFetch({});
    const cal = await boot();
    const box = document.getElementById("checkbox-events-5");
    box.checked = false;
    box.dispatchEvent(new Event("change"));

    expect(shownEvents(cal)).toEqual(["2", "3", "4"]);
    expect(window.location.search).toContain("hidden_staff_events=5");
    expect(document.querySelector(".all_events_checkbox").checked).toBe(false);

    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(shownEvents(cal)).toEqual(["1", "2", "3", "4"]);
  });

  it("removes and restores a staff unavailability source", async () => {
    stubFetch({});
    const cal = await boot();
    const box = document.getElementById("checkbox-5");

    box.checked = false;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.has("5")).toBe(false);
    expect(document.querySelector(".all_checkbox").checked).toBe(false);
    expect(window.location.search).toContain("hidden_staff=5");

    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.has("5")).toBe(true);
  });

  it("the all staff checkbox toggles every staff source", async () => {
    stubFetch({});
    const cal = await boot();
    const all = document.querySelector(".all_checkbox");

    all.checked = false;
    all.dispatchEvent(new Event("change"));
    expect(cal.sources.has("5")).toBe(false);
    expect(cal.sources.has("6")).toBe(false);

    all.checked = true;
    all.dispatchEvent(new Event("change"));
    expect(cal.sources.has("5")).toBe(true);
    expect(cal.sources.has("6")).toBe(true);
  });

  it("gives the all events and all staff checkboxes their own ids and labels", async () => {
    stubFetch({});
    await boot();
    const events = document.querySelector(".all_events_checkbox");
    const staff = document.querySelector(".all_checkbox");
    expect(events.id).not.toBe(staff.id);
    expect(document.querySelectorAll(`[id="${staff.id}"]`).length).toBe(1);
    expect(document.querySelector(`label[for="${events.id}"]`)).not.toBeNull();
    expect(document.querySelector(`label[for="${staff.id}"]`).textContent).toBe(
      "All Staff",
    );
  });

  it("the all events checkbox toggles every staff events checkbox", async () => {
    stubFetch({});
    const cal = await boot();
    const all = document.querySelector(".all_events_checkbox");

    all.checked = false;
    all.dispatchEvent(new Event("change"));
    expect(shownEvents(cal)).toEqual(["3", "4"]);

    all.checked = true;
    all.dispatchEvent(new Event("change"));
    expect(shownEvents(cal)).toEqual(["1", "2", "3", "4"]);
  });

  it("starts with the staff named by the address unchecked", async () => {
    stubFetch({});
    const cal = await boot({
      url: "http://localhost/admin/calendar?hidden_staff=5&hidden_staff_events=6",
    });
    expect(document.getElementById("checkbox-5").checked).toBe(false);
    expect(cal.sources.has("5")).toBe(false);
    expect(document.querySelector(".all_checkbox").checked).toBe(false);
    expect(document.getElementById("checkbox-events-6").checked).toBe(false);
    expect(shownEvents(cal)).toEqual(["1", "3", "4"]);
  });

  it("an imported calendar checkbox adds and removes its source", async () => {
    stubFetch({ imported: calendars });
    const cal = await boot();
    const box = document.getElementById("checkbox-cal1");

    box.checked = false;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.has("cal1")).toBe(false);
    expect(window.location.search).toContain("hidden_calendars=cal1");

    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.has("cal1")).toBe(true);
  });

  it("starts with an imported calendar named by the address removed", async () => {
    stubFetch({ imported: calendars });
    const cal = await boot({
      url: "http://localhost/admin/calendar?hidden_calendars=cal1",
    });
    expect(cal.sources.has("cal1")).toBe(false);
    expect(document.getElementById("checkbox-cal1").checked).toBe(false);
  });
});

describe("calendar options", () => {
  it("opens the event modal for a clicked event and a selected range", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.eventClick({ event: { id: "e" } });
    cal.options.select({ start: "s" });
    expect(eventClick).toHaveBeenCalledWith({ id: "e" });
    expect(eventCreate).toHaveBeenCalledWith({ start: "s" });
  });

  it("toggles weekends and relabels the button", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.customButtons.toggleWeekends.click();
    expect(cal.options.weekends).toBe(false);
    expect(document.querySelector(".fc-toggleWeekends-button").innerHTML).toBe(
      "Show Weekends",
    );
    cal.options.customButtons.toggleWeekends.click();
    expect(document.querySelector(".fc-toggleWeekends-button").innerHTML).toBe(
      "Hide Weekends",
    );
  });

  it("toggles event overlap, remembers it and relabels the button", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.customButtons.toggleEventOverlap.click();
    expect(cal.options.slotEventOverlap).toBe(true);
    expect(localStorage.fullCalendarEventOverlap).toBe("true");
    expect(
      document.querySelector(".fc-toggleEventOverlap-button").innerHTML,
    ).toBe("Disable Event Overlap");
  });

  it("starts with overlap on when it was remembered", async () => {
    localStorage.fullCalendarEventOverlap = "true";
    stubFetch({});
    const cal = await boot();
    expect(cal.options.slotEventOverlap).toBe(true);
  });

  it("decorates a mounted event", async () => {
    // The staff colour gradient as the server builds it.
    const GRADIENT =
      "linear-gradient(to right, #ff0000 0.0%, #ff0000 50.0%, #0000ff 50.0%, #0000ff 100.0%);";
    stubFetch({});
    const cal = await boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: {
        title: "Shift",
        extendedProps: {
          description: "Front desk",
          background: GRADIENT,
          isAdminCreated: true,
        },
      },
    });
    expect(el.classList.contains("fade-in")).toBe(true);
    expect(el.classList.contains("admin-created-unavailability")).toBe(true);
    expect(el.getAttribute("style")).toBe(`background: ${GRADIENT}`);
    expect(tooltips.at(-1).options.title).toBe("Shift<br><i>Front desk</i>");
  });

  it("shows the title and description of an event as text, never as markup", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.eventDidMount({
      el: document.createElement("div"),
      event: {
        title: '<img src=x onerror="alert(1)">Tom & "Jerry"',
        extendedProps: { description: "<script>alert(2)</script>'x'" },
      },
    });
    expect(tooltips.at(-1).options.title).toBe(
      "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;Tom &amp; &quot;Jerry&quot;" +
        "<br><i>&lt;script&gt;alert(2)&lt;/script&gt;&#39;x&#39;</i>",
    );
    const holder = document.createElement("div");
    holder.innerHTML = tooltips.at(-1).options.title;
    expect(holder.querySelector("img, script")).toBeNull();
  });

  it("leaves a plain event undecorated", async () => {
    stubFetch({});
    const cal = await boot();
    const el = document.createElement("div");
    cal.options.eventDidMount({
      el,
      event: { title: "Plain", extendedProps: {} },
    });
    expect(el.getAttribute("style")).toBeNull();
    expect(el.classList.contains("admin-created-unavailability")).toBe(false);
    expect(tooltips.at(-1).options.title).toBe("Plain");
  });

  const range = (type) => ({
    view: { type, currentStart: new Date("2026-11-02T00:00:00Z") },
    startStr: "2026-11-01",
    endStr: "2026-11-08",
  });

  it("remembers the date and fills the range fields when the view changes", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.datesSet(range("timeGridWeek"));

    expect(localStorage.fullCalendarDefaultDateAdmin).toBe(
      "2026-11-02T00:00:00.000Z",
    );
    expect(document.querySelector(".view_start_date").value).toBe("2026-11-01");
    expect(document.querySelector(".view_end_date").value).toBe("2026-11-08");
    expect(document.getElementById("publish_drafts_button").innerText).toBe(
      "Publish This Week's Drafts",
    );
    expect(document.getElementById("delete_drafts_button").innerText).toBe(
      "Delete This Week's Drafts",
    );
  });

  it("names the draft buttons for the month in the month view", async () => {
    stubFetch({});
    const cal = await boot();
    cal.options.datesSet(range("dayGridMonth"));
    expect(document.getElementById("publish_drafts_button").innerText).toBe(
      "Publish This Month's Drafts",
    );
  });

  it("shows hours worked per staff member in the visible range", async () => {
    stubFetch({});
    const cal = await boot();
    const ev = (userId, startHour, endHour) => ({
      start: new Date(`2026-11-02T${startHour}:00:00Z`),
      end: new Date(`2026-11-02T${endHour}:00:00Z`),
      _def: { extendedProps: { assignedUsers: [{ id: userId }] } },
    });
    cal.eventList = [
      ev(5, "09", "12"),
      ev(5, "13", "14"),
      {
        start: new Date("2026-11-03T09:00:00Z"),
        end: new Date("2026-11-03T10:00:00Z"),
        _def: { extendedProps: {} },
      },
      {
        start: new Date("2026-12-03T09:00:00Z"),
        end: new Date("2026-12-03T10:00:00Z"),
        _def: { extendedProps: { assignedUsers: [{ id: 5 }] } },
      },
    ];
    cal.options.datesSet(range("timeGridWeek"));

    const hours = (id) =>
      document
        .getElementById(`checkbox-${id}`)
        .parentNode.querySelector(".user-hours").textContent;
    expect(hours(5)).toBe("4 hrs");
    expect(hours(6)).toBe("0 hrs");

    cal.eventList = [ev(5, "09", "10")];
    cal.options.datesSet(range("timeGridWeek"));
    expect(hours(5)).toBe("1 hrs");
    expect(document.querySelectorAll(".user-hours").length).toBe(2);
  });
});
