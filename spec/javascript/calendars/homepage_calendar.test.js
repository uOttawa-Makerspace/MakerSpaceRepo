// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const calendars = [];
vi.mock("@fullcalendar/core", () => ({
  Calendar: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      this.sources = new Map();
      this.destroyed = false;
      this.rendered = false;
      this.view = { type: options.initialView };
      this.changedTo = null;
      calendars.push(this);
    }
    render() {
      this.rendered = true;
    }
    destroy() {
      this.destroyed = true;
    }
    getEventSourceById(id) {
      if (!this.sources.has(id)) return null;
      return { remove: () => this.sources.delete(id) };
    }
    addEventSource(source) {
      this.sources.set(source.id, source);
    }
    changeView(type) {
      this.changedTo = type;
      this.view.type = type;
    }
  },
}));
vi.mock("@fullcalendar/rrule", () => ({ default: {} }));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));

await import("../../../app/javascript/entrypoints/fullcalendar_setup_homepage.js");

const sources = [
  {
    id: "makerspace",
    color: "#111",
    events: [{ extendedProps: { name: "Makerspace" } }],
  },
  {
    id: "lab",
    backgroundColor: "#222",
    events: [{ extendedProps: { name: "Lab" } }],
  },
  { id: "nameless", events: [{ extendedProps: {} }] },
];

const stubFetch = (response) =>
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => response),
  );

async function show({
  width = 1200,
  path = "/",
  body = sources,
  ok = true,
} = {}) {
  window.happyDOM.setURL(`http://localhost${path}`);
  window.innerWidth = width;
  document.body.innerHTML =
    '<div id="calendar"></div><div id="filters">stale</div>';
  stubFetch({ ok, json: async () => body });
  document.dispatchEvent(new Event("turbo:load"));
  await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
  await new Promise((r) => setTimeout(r, 0));
  return calendars.at(-1);
}

beforeEach(() => {
  calendars.length = 0;
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("open hours calendar", () => {
  it("does nothing on a page without the calendar", async () => {
    document.body.innerHTML = "<p>x</p>";
    stubFetch({});
    document.dispatchEvent(new Event("turbo:load"));
    await new Promise((r) => setTimeout(r, 0));
    expect(fetch).not.toHaveBeenCalled();
  });

  it("loads the open hours as JSON and renders them", async () => {
    const cal = await show();
    expect(fetch).toHaveBeenCalledWith("/open_hours", {
      headers: { Accept: "application/json" },
    });
    expect(cal.rendered).toBe(true);
    expect(cal.options.eventSources).toEqual(sources);
  });

  it.each([
    [1200, "/", "timeGridFiveDay", false],
    [500, "/", "timeGridTwoDay", false],
    [1200, "/hours", "timeGridSevenDay", true],
    [500, "/hours", "timeGridThreeDay", true],
  ])(
    "at width %i on %s starts in the %s view",
    async (width, path, view, allDay) => {
      const cal = await show({ width, path });
      expect(cal.options.initialView).toBe(view);
      expect(cal.options.allDaySlot).toBe(allDay);
    },
  );

  it("switches view when the window crosses the mobile width", async () => {
    const cal = await show({ width: 1200 });
    window.innerWidth = 500;
    cal.options.windowResize();
    expect(cal.changedTo).toBe("timeGridTwoDay");

    cal.changedTo = null;
    cal.options.windowResize();
    expect(cal.changedTo).toBeNull();
  });

  it("says so when there are no open hours", async () => {
    const cal = await show({ body: [] });
    expect(cal).toBeUndefined();
    expect(document.getElementById("calendar").textContent).toContain(
      "No open hours available",
    );
  });

  it("shows nothing for a failed response", async () => {
    const cal = await show({ ok: false });
    expect(cal).toBeUndefined();
    expect(document.getElementById("calendar").innerHTML).toBe("");
  });

  it("logs a failure to load", async () => {
    window.happyDOM.setURL("http://localhost/");
    document.body.innerHTML = '<div id="calendar"></div>';
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    document.dispatchEvent(new Event("turbo:load"));
    await vi.waitFor(() =>
      expect(console.error).toHaveBeenCalledWith(
        "Error initializing calendar:",
        expect.any(Error),
      ),
    );
  });

  it("replaces the previous calendar on the next page load", async () => {
    const first = await show();
    await show();
    expect(first.destroyed).toBe(true);
    expect(calendars).toHaveLength(2);
  });

  it("destroys the calendar before Turbo caches the page", async () => {
    const cal = await show();
    document.dispatchEvent(new Event("turbo:before-cache"));
    expect(cal.destroyed).toBe(true);
    document.dispatchEvent(new Event("turbo:before-cache"));
  });
});

describe("space filters", () => {
  it("lists one checked box per named source, coloured like the source", async () => {
    await show();
    const boxes = [...document.querySelectorAll("#filters input")];
    expect(boxes.map((b) => b.id)).toEqual(["filter-makerspace", "filter-lab"]);
    expect(boxes.every((b) => b.checked)).toBe(true);
    expect(boxes[0].style.backgroundColor).not.toBe("");
    expect(
      [...document.querySelectorAll("#filters label")].map(
        (l) => l.textContent,
      ),
    ).toEqual(["Makerspace", "Lab"]);
    expect(document.getElementById("filters").textContent).not.toContain(
      "stale",
    );
  });

  it("removes a source when unchecked and adds it back when checked", async () => {
    const cal = await show();
    cal.sources.set("makerspace", sources[0]);
    const box = document.getElementById("filter-makerspace");

    box.checked = false;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.has("makerspace")).toBe(false);

    box.checked = true;
    box.dispatchEvent(new Event("change"));
    expect(cal.sources.get("makerspace")).toBe(sources[0]);
  });

  it("does nothing once the calendar has been destroyed", async () => {
    const cal = await show();
    const box = document.getElementById("filter-lab");
    document.dispatchEvent(new Event("turbo:before-cache"));
    box.checked = true;
    expect(() => box.dispatchEvent(new Event("change"))).not.toThrow();
    expect(cal.sources.size).toBe(0);
  });

  it("renders without a filter area", async () => {
    window.happyDOM.setURL("http://localhost/");
    document.body.innerHTML = '<div id="calendar"></div>';
    stubFetch({ ok: true, json: async () => sources });
    document.dispatchEvent(new Event("turbo:load"));
    await vi.waitFor(() => expect(calendars.at(-1)?.rendered).toBe(true));
  });
});
