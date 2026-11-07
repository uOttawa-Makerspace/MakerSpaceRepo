// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EVENT_MODAL_HTML } from "./event_modal_fixture.js";

const collapseHide = vi.fn();
vi.mock("bootstrap", () => ({
  Modal: class {},
  Collapse: class {
    hide() {
      collapseHide();
    }
  },
}));

// TomSelect decorates the staff <select>; only the calls the page makes matter.
const tomInstances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      this.added = [];
      this.destroyed = false;
      this.handlers = {};
      this.synced = 0;
      tomInstances.push(this);
    }
    on(name, fn) {
      this.handlers[name] = fn;
    }
    sync() {
      this.synced += 1;
    }
    clearOptions() {
      this.added = [];
    }
    addOption(options) {
      this.added = options;
    }
    destroy() {
      this.destroyed = true;
    }
    setTextboxValue() {}
  },
}));

await import("../../../app/javascript/src/manage_calendar_events.js");

const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));
const iso = (local) => new Date(local).toISOString();

const staffFeed = [
  {
    id: 1,
    name: "Ada",
    color: "#ff0000",
    unavailabilities: [
      { start: iso("2027-03-17T13:00"), end: iso("2027-03-17T15:00") },
    ],
  },
  { id: 2, name: "Bob", color: "#00ff00", unavailabilities: [] },
];

async function load(feed = staffFeed, response = {}) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => feed, ...response })),
  );
  document.dispatchEvent(new Event("turbo:load"));
  await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function setTimes(start, end) {
  $("start_time_field").value = start;
  $("end_time_field").value = end;
  fire($("end_time_field"), "change");
}

const optionNames = () =>
  [...$("staff_select").options].map((o) => o.textContent);
const unavailableDates = (name) =>
  [...$("staff_select").options].find((o) => o.textContent === name).dataset
    .unavailableDates;

beforeEach(async () => {
  document.body.innerHTML = EVENT_MODAL_HTML;
  $("addEventButton").disabled = true; // the page renders it disabled
  tomInstances.length = 0;
  collapseHide.mockClear();
});

describe("loading", () => {
  it("asks for the staff and their unavailabilities of the space", async () => {
    await load();
    expect(fetch).toHaveBeenCalledWith(
      "/admin/calendar/utc_unavailabilities_json/7",
    );
  });
});

describe("when the staff data cannot be loaded", () => {
  it("shows the error and keeps the add button disabled for a failed response", async () => {
    await load(staffFeed, { ok: false });

    expect($("staff_load_error").classList.contains("d-none")).toBe(false);
    expect($("addEventButton").disabled).toBe(true);
    expect($("eventModal").dataset.ready).toBeUndefined();
  });

  it("shows the error for a network failure", async () => {
    const consoleError = vi
      .spyOn(console, "error")
      .mockImplementation(() => {});
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("offline");
      }),
    );
    document.dispatchEvent(new Event("turbo:load"));
    await vi.waitFor(() =>
      expect($("staff_load_error").classList.contains("d-none")).toBe(false),
    );

    expect($("addEventButton").disabled).toBe(true);
    expect(consoleError).toHaveBeenCalled();
    consoleError.mockRestore();
  });
});

describe("a page restored from the Turbo cache", () => {
  it("is not ready when the load then fails", async () => {
    $("eventModal").dataset.ready = "true";
    $("addEventButton").disabled = false;

    await load(staffFeed, { ok: false });

    expect($("eventModal").dataset.ready).toBeUndefined();
    expect($("addEventButton").disabled).toBe(true);
    expect($("staff_load_error").classList.contains("d-none")).toBe(false);
  });

  it("is reset before Turbo caches the page", () => {
    $("eventModal").dataset.ready = "true";
    $("addEventButton").disabled = false;

    document.dispatchEvent(new Event("turbo:before-cache"));

    expect($("eventModal").dataset.ready).toBeUndefined();
    expect($("addEventButton").disabled).toBe(true);
  });
});

describe("a successful load after a failed one", () => {
  it("hides the error again and enables the add button", async () => {
    await load(staffFeed, { ok: false });
    expect($("staff_load_error").classList.contains("d-none")).toBe(false);

    await load();

    expect($("staff_load_error").classList.contains("d-none")).toBe(true);
    expect($("addEventButton").disabled).toBe(false);
    expect($("eventModal").dataset.ready).toBe("true");
  });
});

describe("staff options", () => {
  it("lists available staff first, then the unavailable ones, each by name", async () => {
    await load();
    setTimes("2027-03-17T14:00", "2027-03-17T14:30");

    expect(optionNames()).toEqual(["Bob", "Ada"]);
    expect(unavailableDates("Bob")).toBe("");
    expect(unavailableDates("Ada")).not.toBe("");
    expect($("staff_select").options[1].dataset.color).toBe("#ff0000");
  });

  it("keeps the staff that were selected when the list is rebuilt", async () => {
    await load();
    setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    [...$("staff_select").options].find(
      (o) => o.textContent === "Ada",
    ).selected = true;
    setTimes("2027-03-17T10:00", "2027-03-17T12:00");
    expect(
      [...$("staff_select").selectedOptions].map((o) => o.textContent),
    ).toEqual(["Ada"]);
  });

  it("shows 'No staff yet' when the space has no staff", async () => {
    await load([]);
    setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    expect(optionNames()).toEqual(["No staff yet"]);
    expect($("staff_select").options[0].value).toBe("");
  });

  it("starts the picker on the first change and re-fills it afterwards", async () => {
    await load();
    setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    expect(tomInstances).toHaveLength(1);
    setTimes("2027-03-17T10:00", "2027-03-17T12:00");
    expect(tomInstances).toHaveLength(1);
    expect(tomInstances[0].added.map((o) => o.text)).toEqual(["Ada", "Bob"]);
  });

  it("renders an option with the first unavailable date and a count of the rest", async () => {
    await load();
    setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    const render = tomInstances[0].config.render.option;
    const escape = (s) => String(s);
    const html = render(
      {
        text: "Ada",
        color: "#f00",
        unavailableDates: "2027-03-17T14:00:00Z,2027-03-18T14:00:00Z",
      },
      escape,
    );
    expect(html).toContain("Ada");
    expect(html).toContain("(Unavailable");
    expect(html).toContain("+1");
    expect(render({ text: "Bob", unavailableDates: "" }, escape)).not.toContain(
      "Unavailable",
    );
    expect(render({ text: "Bob", unavailableDates: "" }, escape)).toContain(
      "#000",
    );
  });

  it("rebuilds the repeat rule when the picker takes focus", async () => {
    await load();
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    $("recurrence_frequency").value = "DAILY";
    tomInstances[0].handlers.focus();
    expect($("recurrence_rule_field").value).toContain("FREQ=DAILY");
  });
});

describe("unavailable dates", () => {
  it("flags staff whose one-off unavailability overlaps a one-off event", async () => {
    await load();
    setTimes("2027-03-17T14:00", "2027-03-17T14:30");
    expect(unavailableDates("Ada")).toContain("2027");
  });

  it("does not flag a one-off event that only touches the unavailability", async () => {
    await load();
    setTimes("2027-03-17T15:00", "2027-03-17T16:00");
    expect(unavailableDates("Ada")).toBe("");
  });

  it("flags a repeating event that has an occurrence inside a one-off unavailability", async () => {
    await load();
    fire($("eventModal"), "show.bs.modal");
    $("start_time_field").value = "2027-03-17T14:00";
    $("end_time_field").value = "2027-03-17T14:30";
    $("recurrence_frequency").value = "DAILY";
    // the rule is built when the picker takes focus
    tomInstances[0].handlers.focus();
    expect(unavailableDates("Ada")).not.toBe("");
    expect(unavailableDates("Bob")).toBe("");
  });

  it("flags a one-off event inside a repeating unavailability", async () => {
    const feed = [
      {
        id: 1,
        name: "Ada",
        color: "#f00",
        unavailabilities: [
          {
            start: iso("2027-03-15T13:00"),
            end: iso("2027-03-15T15:00"),
            duration: 2 * 3600 * 1000,
            rrule: "DTSTART:20270315T130000Z\nRRULE:FREQ=DAILY;COUNT=30",
          },
        ],
      },
    ];
    await load(feed);
    // 13:00Z to 15:00Z each day; the browser reads the field in its own zone
    const day = new Date(Date.UTC(2027, 2, 17, 14, 0));
    const pad = (n) => String(n).padStart(2, "0");
    const local = `${day.getFullYear()}-${pad(day.getMonth() + 1)}-${pad(day.getDate())}T${pad(day.getHours())}:${pad(day.getMinutes())}`;
    const later = new Date(day.getTime() + 1800000);
    const localEnd = `${later.getFullYear()}-${pad(later.getMonth() + 1)}-${pad(later.getDate())}T${pad(later.getHours())}:${pad(later.getMinutes())}`;
    setTimes(local, localEnd);
    expect(unavailableDates("Ada")).not.toBe("");
  });

  it("warns and carries on when a repeating unavailability has an unreadable rule", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const feed = [
      {
        id: 1,
        name: "Ada",
        color: "#f00",
        unavailabilities: [
          {
            start: iso("2027-03-15T13:00"),
            end: iso("2027-03-15T15:00"),
            duration: 7200000,
            rrule: "RRULE:FREQ=NEVER",
          },
        ],
      },
    ];
    await load(feed);
    setTimes("2027-03-17T14:00", "2027-03-17T14:30");
    expect(warn).toHaveBeenCalledWith("Invalid RRULE:", expect.anything());
    expect(unavailableDates("Ada")).toBe("");
  });
});

describe("form behaviour", () => {
  it("disables saving for an end that is not after the start", async () => {
    await load();
    setTimes("2027-03-17T11:00", "2027-03-17T10:00");
    expect($("save_button").disabled).toBe(true);
    expect($("time_error").classList.contains("d-none")).toBe(false);
  });

  it("makes an all-day entry midnight to midnight", async () => {
    await load();
    $("start_time_field").value = "2027-03-17T10:30";
    $("all_day_checkbox").checked = true;
    fire($("all_day_checkbox"), "change");
    expect($("start_time_field").value).toBe("2027-03-17T00:00");
    expect($("end_time_field").value).toBe("2027-03-18T00:00");
    expect($("end_time_field").disabled).toBe(true);
  });

  it("shows the training fields only for the training type", async () => {
    await load();
    $("event_type_select").value = "training";
    fire($("event_type_select"), "change");
    expect($("training-fields").style.display).toBe("");
    $("event_type_select").value = "meeting";
    fire($("event_type_select"), "change");
    expect($("training-fields").style.display).toBe("none");
  });

  it("starts the picker and proposes times when the modal opens", async () => {
    await load();
    fire($("eventModal"), "show.bs.modal");
    expect($("start_time_field").value).not.toBe("");
    expect(tomInstances).toHaveLength(1);
    expect(optionNames()).toEqual(["Ada", "Bob"]);
  });

  it("asks before closing and resets everything once hidden", async () => {
    await load();
    vi.stubGlobal(
      "confirm",
      vi.fn(() => false),
    );
    const hide = new Event("hide.bs.modal", { cancelable: true });
    $("eventModal").dispatchEvent(hide);
    expect(hide.defaultPrevented).toBe(true);

    fire($("eventModal"), "show.bs.modal");
    $("all_day_checkbox").checked = true;
    $("save_button").disabled = true;
    fire($("eventModal"), "hidden.bs.modal");
    expect($("all_day_checkbox").checked).toBe(false);
    expect($("save_button").disabled).toBe(false);
    expect($("recurrence_options").style.display).toBe("none");
    expect(collapseHide).toHaveBeenCalled();
    expect(tomInstances[0].destroyed).toBe(true);
  });
});

describe("submit", () => {
  async function ready() {
    await load();
    fire($("eventModal"), "show.bs.modal");
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
  }
  const submit = () => fire($("eventForm"), "submit", { cancelable: true });

  it("writes UTC instants, syncs the picker and builds the rule", async () => {
    await ready();
    $("recurrence_frequency").value = "WEEKLY";
    $("day_MO").checked = true;
    submit();
    expect($("utc_start_time").value).toBe(iso("2027-03-17T10:00"));
    expect($("utc_end_time").value).toBe(iso("2027-03-17T11:00"));
    expect($("recurrence_rule_field").value).toContain("FREQ=WEEKLY");
    expect(tomInstances[0].synced).toBeGreaterThan(0);
  });

  it("clears a title made of 'for' and staff names", async () => {
    await ready();
    $("title").value = "Soldering for Ada, Bob";
    submit();
    expect($("title").value).toBe("");
  });

  it("clears a title that ends with the name of one staff member", async () => {
    await ready();
    $("title").value = "Open lab for Bob";
    submit();
    expect($("title").value).toBe("");
  });

  it("keeps a title with a name the staff list does not have", async () => {
    await ready();
    $("title").value = "Open lab for Carol";
    submit();
    expect($("title").value).toBe("Open lab for Carol");
  });

  it("keeps a title that mentions a name without the word 'for'", async () => {
    await ready();
    $("title").value = "Ada's workshop";
    submit();
    expect($("title").value).toBe("Ada's workshop");
  });

  it("keeps a title that has text after the names", async () => {
    await ready();
    $("title").value = "Open lab for Ada (cancelled)";
    submit();
    expect($("title").value).toBe("Open lab for Ada (cancelled)");
  });

  it("leaves a blank title alone", async () => {
    await ready();
    $("title").value = "   ";
    submit();
    expect($("title").value).toBe("   ");
  });
});
