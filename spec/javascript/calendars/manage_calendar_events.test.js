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
    refreshOptions() {
      this.refreshed = (this.refreshed || 0) + 1;
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
// The space's staff as the page lists them (data-staff on the picker), and the
// server's ranking for an event in the form: Bob is free, Ada is not.
const staffList = [
  { id: 1, name: "Ada", color: "#ff0000", unavailableStarts: [] },
  { id: 2, name: "Bob", color: "#00ff00", unavailableStarts: [] },
];
const ranking = [
  { id: 2, name: "Bob", color: "#00ff00", unavailableStarts: [] },
  {
    id: 1,
    name: "Ada",
    color: "#ff0000",
    unavailableStarts: ["2027-03-17T18:00:00Z"],
  },
];
const answer = (body, init = {}) => ({
  ok: true,
  json: async () => body,
  ...init,
});
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function load(staff = staffList, response = answer(ranking)) {
  $("staff_select").dataset.staff = JSON.stringify(staff);
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => response),
  );
  document.dispatchEvent(new Event("turbo:load"));
  await settle();
}

async function setTimes(start, end) {
  $("start_time_field").value = start;
  $("end_time_field").value = end;
  fire($("end_time_field"), "change");
  await settle();
}

const optionNames = () =>
  [...$("staff_select").options].map((o) => o.textContent);
const unavailableDates = (name) =>
  [...$("staff_select").options].find((o) => o.textContent === name).dataset
    .unavailableDates;
const askedFor = () => new URL(fetch.mock.lastCall[0], "http://x").searchParams;

beforeEach(async () => {
  document.body.innerHTML = EVENT_MODAL_HTML;
  $("addEventButton").disabled = true; // the page renders it disabled
  tomInstances.length = 0;
  collapseHide.mockClear();
});

describe("loading", () => {
  it("does nothing on a page without the calendar", async () => {
    document.body.innerHTML = "";
    vi.stubGlobal("fetch", vi.fn());
    document.dispatchEvent(new Event("turbo:load"));
    await settle();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("is ready at once, with the staff the page lists and no request", async () => {
    await load();
    expect(fetch).not.toHaveBeenCalled();
    expect($("addEventButton").disabled).toBe(false);
    expect($("eventModal").dataset.ready).toBe("true");
    fire($("eventModal"), "show.bs.modal");
    expect(optionNames()).toEqual(["Ada", "Bob"]);
  });
});

describe("a page restored from the Turbo cache", () => {
  it("is reset before Turbo caches the page", () => {
    $("eventModal").dataset.ready = "true";
    $("addEventButton").disabled = false;

    document.dispatchEvent(new Event("turbo:before-cache"));

    expect($("eventModal").dataset.ready).toBeUndefined();
    expect($("addEventButton").disabled).toBe(true);
  });
});

describe("the staff ranking", () => {
  it("asks the server for the instants of the Toronto times, the rule and the space", async () => {
    await load();
    $("recurrence_frequency").value = "DAILY";
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    fire($("recurrence_frequency"), "change");
    await settle();
    expect(fetch.mock.lastCall[0]).toMatch(
      /^\/admin\/calendar\/staff_conflicts\?/,
    );
    expect(Object.fromEntries(askedFor())).toEqual({
      space_id: "7",
      start: "2027-03-17T14:00:00.000Z",
      end: "2027-03-17T15:00:00.000Z",
      recurrence_rule:
        "DTSTART;TZID=America/Toronto:20270317T100000\nRRULE:FREQ=DAILY",
    });
  });

  it("lists the staff in the server's order, available first, with their unavailable dates", async () => {
    await load();
    await setTimes("2027-03-17T14:00", "2027-03-17T14:30");

    expect(optionNames()).toEqual(["Bob", "Ada"]);
    expect(unavailableDates("Bob")).toBe("");
    expect(unavailableDates("Ada")).toBe("2027-03-17T18:00:00Z");
    expect($("staff_select").options[1].dataset.color).toBe("#ff0000");
    // the open picker is drawn again with the answer
    expect(tomInstances[0].added.map((o) => o.text)).toEqual(["Bob", "Ada"]);
    expect(tomInstances[0].refreshed).toBeGreaterThan(0);
  });

  it("asks again when the repeat changes", async () => {
    await load();
    await setTimes("2027-03-17T14:00", "2027-03-17T14:30");
    const asked = fetch.mock.calls.length;
    $("recurrence_until").value = "2027-03-31";
    fire($("recurrence_until"), "change");
    await settle();
    expect(fetch.mock.calls.length).toBe(asked + 1);
  });

  it("does not ask for an event that ends before it starts", async () => {
    await load();
    await setTimes("2027-03-17T11:00", "2027-03-17T10:00");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("draws only the latest answer", async () => {
    await load();
    let answerFirst;
    const first = new Promise((resolve) => (answerFirst = resolve));
    fetch
      .mockImplementationOnce(() => first)
      .mockImplementationOnce(async () => answer(ranking));
    $("start_time_field").value = "2027-03-17T14:00";
    $("end_time_field").value = "2027-03-17T14:30";
    fire($("end_time_field"), "change");
    fire($("end_time_field"), "change");
    await settle();
    answerFirst(answer(staffList));
    await settle();
    expect(optionNames()).toEqual(["Bob", "Ada"]);
  });

  it("keeps the list, shows the error and stays usable when the server cannot answer", async () => {
    const consoleError = vi
      .spyOn(console, "error")
      .mockImplementation(() => {});
    await load(staffList, answer([], { ok: false, status: 500 }));
    await setTimes("2027-03-17T14:00", "2027-03-17T14:30");

    expect($("staff_load_error").classList.contains("d-none")).toBe(false);
    expect(optionNames()).toEqual(["Ada", "Bob"]);
    expect($("addEventButton").disabled).toBe(false);
    expect(consoleError).toHaveBeenCalled();

    fetch.mockImplementation(async () => answer(ranking));
    await setTimes("2027-03-17T14:00", "2027-03-17T15:00");
    expect($("staff_load_error").classList.contains("d-none")).toBe(true);
    consoleError.mockRestore();
  });

  it("drops the labels of an earlier answer when the latest request fails", async () => {
    const consoleError = vi
      .spyOn(console, "error")
      .mockImplementation(() => {});
    await load();
    await setTimes("2027-03-17T14:00", "2027-03-17T14:30");
    expect(unavailableDates("Ada")).toBe("2027-03-17T18:00:00Z");

    fetch.mockImplementation(async () =>
      answer([], { ok: false, status: 500 }),
    );
    await setTimes("2027-03-18T14:00", "2027-03-18T14:30");

    expect(optionNames()).toEqual(["Ada", "Bob"]);
    expect(unavailableDates("Ada")).toBe("");
    expect($("staff_load_error").classList.contains("d-none")).toBe(false);
    consoleError.mockRestore();
  });

  it("shows the error for a network failure", async () => {
    const consoleError = vi
      .spyOn(console, "error")
      .mockImplementation(() => {});
    await load();
    fetch.mockImplementation(async () => {
      throw new Error("offline");
    });
    await setTimes("2027-03-17T14:00", "2027-03-17T14:30");
    expect($("staff_load_error").classList.contains("d-none")).toBe(false);
    consoleError.mockRestore();
  });
});

describe("staff options", () => {
  it("keeps the staff that were selected when the list is rebuilt", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    [...$("staff_select").options].find(
      (o) => o.textContent === "Ada",
    ).selected = true;
    await setTimes("2027-03-17T10:00", "2027-03-17T12:00");
    expect(
      [...$("staff_select").selectedOptions].map((o) => o.textContent),
    ).toEqual(["Ada"]);
  });

  it("shows 'No staff yet' when the space has no staff", async () => {
    await load([], answer([]));
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    expect(optionNames()).toEqual(["No staff yet"]);
    expect($("staff_select").options[0].value).toBe("");
  });

  it("starts the picker on the first change and re-fills it afterwards", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    expect(tomInstances).toHaveLength(1);
    await setTimes("2027-03-17T10:00", "2027-03-17T12:00");
    expect(tomInstances).toHaveLength(1);
    expect(tomInstances[0].added.map((o) => o.text)).toEqual(["Bob", "Ada"]);
  });

  it("renders an option with the first unavailable date and a count of the rest", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
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

  it("renders an option that carries no unavailable dates", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    const render = tomInstances[0].config.render.option;
    const html = render({ text: "Ada", color: "#f00" }, (s) => String(s));
    expect(html).toContain("Ada");
    expect(html).not.toContain("Unavailable");
  });

  it("uses a staff colour in the option style only when it is a hex colour", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    const render = tomInstances[0].config.render.option;
    const escape = (s) => String(s);
    const style = (color) =>
      render({ text: "Ada", color, unavailableDates: "" }, escape).match(
        /style="([^"]*)"/,
      )[1];
    expect(style("#e6194b")).toBe("color: #e6194b");
    expect(style('red;background:url(x)"')).toBe("color: #000");
    expect(style("red")).toBe("color: #000");
  });

  it("shows the first unavailable date as a Toronto date", async () => {
    await load();
    await setTimes("2027-03-17T10:00", "2027-03-17T11:00");
    const render = tomInstances[0].config.render.option;
    // 02:30 UTC on the 18th is 22:30 on the 17th in Toronto
    const html = render(
      { text: "Ada", unavailableDates: "2027-03-18T02:30:00Z" },
      String,
    );
    const toronto = new Date("2027-03-17T12:00:00Z").toLocaleDateString();
    expect(html).toContain(`(Unavailable ${toronto}`);
  });

  it("marks the list ranked only once the latest answer is drawn", async () => {
    await load();
    let answerLater;
    fetch.mockImplementationOnce(
      () => new Promise((resolve) => (answerLater = resolve)),
    );
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    fire($("end_time_field"), "change");
    expect($("staff_select").dataset.ranked).toBeUndefined();
    answerLater(answer(ranking));
    await settle();
    expect($("staff_select").dataset.ranked).toBe("true");
  });
});

describe("form behaviour", () => {
  it("disables saving for an end that is not after the start", async () => {
    await load();
    await setTimes("2027-03-17T11:00", "2027-03-17T10:00");
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

  it("writes the UTC instants of the Toronto times, syncs the picker and builds the rule", async () => {
    await ready();
    $("recurrence_frequency").value = "WEEKLY";
    $("day_MO").checked = true;
    submit();
    expect($("utc_start_time").value).toBe("2027-03-17T14:00:00.000Z");
    expect($("utc_end_time").value).toBe("2027-03-17T15:00:00.000Z");
    expect($("recurrence_rule_field").value).toContain("FREQ=WEEKLY");
    expect(tomInstances[0].synced).toBeGreaterThan(0);
  });

  it("asks to keep the series' own times only when the times are as the dialog filled them", async () => {
    await ready();
    $("keep_series_times").dataset.filled =
      "2027-03-17T10:00|2027-03-17T11:00|false";
    submit();
    expect($("keep_series_times").disabled).toBe(false);

    $("end_time_field").value = "2027-03-17T12:00";
    submit();
    expect($("keep_series_times").disabled).toBe(true);
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
  it("closes a saved dialog without asking", async () => {
    await load();
    const modal = $("eventModal");
    vi.stubGlobal("confirm", vi.fn());
    modal.dataset.saved = "true";
    const hide = new Event("hide.bs.modal", { cancelable: true });
    modal.dispatchEvent(hide);
    expect(confirm).not.toHaveBeenCalled();
    expect(hide.defaultPrevented).toBe(false);
  });

  it("marks the event window ready once shown and clears it on a confirmed close", async () => {
    await load();
    const modal = $("eventModal");
    fire(modal, "shown.bs.modal");
    expect(modal.dataset.shown).toBe("true");

    vi.stubGlobal(
      "confirm",
      vi.fn(() => false),
    );
    modal.dispatchEvent(new Event("hide.bs.modal", { cancelable: true }));
    expect(modal.dataset.shown).toBe("true");

    vi.stubGlobal(
      "confirm",
      vi.fn(() => true),
    );
    modal.dispatchEvent(new Event("hide.bs.modal", { cancelable: true }));
    expect(modal.dataset.shown).toBeUndefined();

    fire(modal, "shown.bs.modal");
    fire(modal, "hidden.bs.modal");
    expect(modal.dataset.shown).toBeUndefined();
  });
});
