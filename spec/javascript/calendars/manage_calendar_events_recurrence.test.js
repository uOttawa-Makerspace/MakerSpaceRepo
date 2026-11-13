// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EVENT_MODAL_HTML } from "./event_modal_fixture.js";

vi.mock("bootstrap", () => ({
  Modal: class {},
  Collapse: class {
    hide() {}
  },
}));

const tomInstances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.config = config;
      this.added = [];
      this.destroyed = false;
      this.handlers = {};
      this.textbox = "unset";
      tomInstances.push(this);
    }
    on(name, fn) {
      this.handlers[name] = fn;
    }
    sync() {}
    clearOptions() {}
    addOption(options) {
      this.added = options;
    }
    refreshOptions() {
      this.refreshed = (this.refreshed || 0) + 1;
    }
    destroy() {
      this.destroyed = true;
    }
    setTextboxValue(value) {
      this.textbox = value;
    }
  },
}));

await import("../../../app/javascript/src/manage_calendar_events.js");

const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));

// The page lists the staff on the picker; the server ranks them.
async function load(staff) {
  $("staff_select").dataset.staff = JSON.stringify(staff);
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => staff })),
  );
  document.dispatchEvent(new Event("turbo:load"));
  await new Promise((resolve) => setTimeout(resolve, 0));
}

const ada = () => [
  { id: 1, name: "Ada", color: "#f00", unavailableStarts: [] },
];

beforeEach(() => {
  document.body.innerHTML = EVENT_MODAL_HTML;
  tomInstances.length = 0;
});

afterEach(() => vi.useRealTimers());

describe("all day", () => {
  it("restores a one hour entry when all day is switched off", async () => {
    await load(ada());
    $("start_time_field").value = "2027-03-17T10:30";
    $("all_day_checkbox").checked = true;
    fire($("all_day_checkbox"), "change");
    $("all_day_checkbox").checked = false;
    fire($("all_day_checkbox"), "change");

    expect($("end_time_field").disabled).toBe(false);
    expect($("start_time_field").value).toBe("2027-03-17T00:00");
    expect($("end_time_field").value).toBe("2027-03-17T01:00");
  });

  it("keeps an all day entry at midnight when the start date changes", async () => {
    await load(ada());
    $("all_day_checkbox").checked = true;
    $("start_time_field").value = "2027-03-20T15:00";
    fire($("start_time_field"), "change");
    expect($("start_time_field").value).toBe("2027-03-20T00:00");
    expect($("end_time_field").value).toBe("2027-03-21T00:00");
  });

  it("ticks the weekday of an all day weekly entry", async () => {
    await load(ada());
    $("recurrence_frequency").value = "WEEKLY";
    $("start_time_field").value = "2027-03-17T10:00"; // a Wednesday
    $("all_day_checkbox").checked = true;
    fire($("all_day_checkbox"), "change");

    const ticked = [...document.querySelectorAll(".dayCheckbox")]
      .filter((c) => c.checked)
      .map((c) => c.value);
    expect(ticked).toEqual(["WE"]);
  });
});

describe("repeat options", () => {
  const change = async (value) => {
    $("recurrence_frequency").value = value;
    fire($("recurrence_frequency"), "change");
  };

  it("shows the repeat options and ticks the start weekday for weekly", async () => {
    await load(ada());
    $("start_time_field").value = "2027-03-17T10:00";
    await change("WEEKLY");

    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("day_WE").checked).toBe(true);
    expect($("day_MO").checked).toBe(false);
  });

  it("hides the weekday choices for daily and everything for no repeat", async () => {
    await load(ada());
    $("start_time_field").value = "2027-03-17T10:00";
    await change("WEEKLY");
    await change("DAILY");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("none");
    expect($("day_WE").checked).toBe(false);

    await change("");
    expect($("recurrence_options").style.display).toBe("none");
  });

  it("warns when no weekday is ticked and clears the warning when one is", async () => {
    await load(ada());
    $("start_time_field").value = "2027-03-17T10:00";
    await change("WEEKLY");

    $("day_WE").checked = false;
    fire($("day_WE"), "change");
    expect($("day_freq_error").classList.contains("d-none")).toBe(false);

    $("day_MO").checked = true;
    fire($("day_MO"), "change");
    expect($("day_freq_error").classList.contains("d-none")).toBe(true);
  });

  it("builds a weekly rule with the chosen days and the end date", async () => {
    await load(ada());
    fire($("eventModal"), "show.bs.modal");
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    $("recurrence_frequency").value = "WEEKLY";
    $("day_MO").checked = true;
    $("day_WE").checked = true;
    $("recurrence_until").value = "2027-06-30";
    fire($("recurrence_until"), "change");

    const rule = $("recurrence_rule_field").value;
    expect(rule).toContain("FREQ=WEEKLY");
    expect(rule).toContain("BYDAY=MO,WE");
    // The series starts in Toronto time and ends at the end of the picked
    // day in Toronto (23:59:59 EDT on June 30 is 03:59:59 UTC on July 1).
    expect(rule).toContain("DTSTART;TZID=America/Toronto:20270317T100000");
    expect(rule).toContain("UNTIL=20270701T035959Z");
  });

  it("leaves the rule empty when the event does not repeat", async () => {
    await load(ada());
    fire($("eventModal"), "show.bs.modal");
    $("recurrence_rule_field").value = "stale";
    $("recurrence_frequency").value = "";
    fire($("recurrence_frequency"), "change");
    expect($("recurrence_rule_field").value).toBe("");
  });

  it("falls back to daily for a frequency the rule library does not know", async () => {
    await load(ada());
    fire($("eventModal"), "show.bs.modal");
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    const option = document.createElement("option");
    option.value = "FORTNIGHTLY";
    $("recurrence_frequency").add(option);
    $("recurrence_frequency").value = "FORTNIGHTLY";
    fire($("recurrence_frequency"), "change");
    expect($("recurrence_rule_field").value).toContain("FREQ=DAILY");
  });
});

describe("staff picker", () => {
  it("clears the typed text after a staff member is picked", async () => {
    await load(ada());
    fire($("eventModal"), "show.bs.modal");
    tomInstances[0].config.onItemAdd.call(tomInstances[0]);
    expect(tomInstances[0].textbox).toBe("");
  });

  it("replaces the picker when the modal opens again", async () => {
    await load(ada());
    fire($("eventModal"), "show.bs.modal");
    fire($("eventModal"), "show.bs.modal");
    expect(tomInstances).toHaveLength(2);
    expect(tomInstances[0].destroyed).toBe(true);
  });

  it("keeps a title when the space has no staff to match", async () => {
    await load([]);
    fire($("eventModal"), "show.bs.modal");
    $("title").value = "Shift for Ada";
    fire($("eventForm"), "submit", { cancelable: true });
    expect($("title").value).toBe("Shift for Ada");
  });

  it("does not close the update dropdown when a radio is clicked", async () => {
    await load(ada());
    const parentClicks = vi.fn();
    $("update_dropdown_items").addEventListener("click", parentClicks);
    $("update_all").click();
    expect(parentClicks).not.toHaveBeenCalled();
  });
});
