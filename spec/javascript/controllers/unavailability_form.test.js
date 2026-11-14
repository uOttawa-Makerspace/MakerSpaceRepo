// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";
import { UNAVAILABILITY_MODAL_HTML } from "../calendars/event_modal_fixture.js";

const collapseHide = vi.fn();
const shown = [];
vi.mock("bootstrap", () => ({
  Modal: class {
    static getOrCreateInstance(el) {
      return { show: () => shown.push(el.id) };
    }
  },
  Collapse: class {
    hide() {
      collapseHide();
    }
  },
}));

const { default: UnavailabilityForm } =
  await import("../../../app/javascript/controllers/unavailability_form_controller.js");
const { instantToWall } =
  await import("../../../app/javascript/src/recurrence.js");

const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));

function setStart(local) {
  $("start_time_field").value = local;
  fire($("start_time_field"), "change");
}

let application;

beforeEach(async () => {
  document.body.innerHTML = UNAVAILABILITY_MODAL_HTML;
  collapseHide.mockClear();
  shown.length = 0;
  application = Application.start();
  application.register("unavailability-form", UnavailabilityForm);
  await new Promise((resolve) => setTimeout(resolve, 0));
});

const controller = () =>
  application.getControllerForElementAndIdentifier(
    $("unavailabilityModal"),
    "unavailability-form",
  );

afterEach(() => {
  application.stop();
  document.body.innerHTML = "";
});

describe("time range", () => {
  it("shows the error and disables saving when the end is not after the start", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T10:00";
    fire($("end_time_field"), "change");
    expect($("time_error").classList.contains("d-none")).toBe(false);
    expect($("save_button").disabled).toBe(true);
    expect($("save_button").classList.contains("disabled")).toBe(true);
  });

  it("clears the error once the end is later", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T09:00";
    fire($("end_time_field"), "change");
    $("end_time_field").value = "2027-03-17T11:00";
    fire($("end_time_field"), "change");
    expect($("time_error").classList.contains("d-none")).toBe(true);
    expect($("save_button").disabled).toBe(false);
  });

  it("checks the range again when the start changes", () => {
    $("end_time_field").value = "2027-03-17T09:00";
    setStart("2027-03-17T10:00");
    expect($("save_button").disabled).toBe(true);
  });
});

describe("all day", () => {
  it("snaps the start to midnight, ends the next midnight and locks the end", () => {
    $("start_time_field").value = "2027-03-17T10:30";
    $("all_day_checkbox").checked = true;
    fire($("all_day_checkbox"), "change");
    expect($("start_time_field").value).toBe("2027-03-17T00:00");
    expect($("end_time_field").value).toBe("2027-03-18T00:00");
    expect($("end_time_field").disabled).toBe(true);
  });

  it("keeps all-day when the start date changes", () => {
    $("all_day_checkbox").checked = true;
    setStart("2027-03-20T08:15");
    expect($("start_time_field").value).toBe("2027-03-20T00:00");
    expect($("end_time_field").value).toBe("2027-03-21T00:00");
  });

  it("ticks only the weekday of the start for a weekly all-day entry", () => {
    $("recurrence_frequency").value = "WEEKLY";
    $("start_time_field").value = "2027-03-17T10:30";
    $("all_day_checkbox").checked = true;
    fire($("all_day_checkbox"), "change");
    const ticked = [...document.querySelectorAll(".dayCheckbox")]
      .filter((c) => c.checked)
      .map((c) => c.value);
    expect(ticked).toEqual(["WE"]);
  });

  it("makes the slot one hour long again when all-day is cleared", () => {
    $("start_time_field").value = "2027-03-17T00:00";
    $("end_time_field").disabled = true;
    fire($("all_day_checkbox"), "change");
    expect($("end_time_field").disabled).toBe(false);
    expect($("end_time_field").value).toBe("2027-03-17T01:00");
  });
});

describe("repeat options", () => {
  it("shows the options for a frequency and the day boxes only for weekly", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("recurrence_frequency").value = "WEEKLY";
    fire($("recurrence_frequency"), "change");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("day_WE").checked).toBe(true);

    $("recurrence_frequency").value = "DAILY";
    fire($("recurrence_frequency"), "change");
    expect($("weekly_options").style.display).toBe("none");
    expect($("day_WE").checked).toBe(false);

    $("recurrence_frequency").value = "";
    fire($("recurrence_frequency"), "change");
    expect($("recurrence_options").style.display).toBe("none");
  });

  it("warns when no weekday is ticked, and clears the warning when one is", () => {
    fire($("day_MO"), "change");
    expect($("day_freq_error").classList.contains("d-none")).toBe(false);
    $("day_MO").checked = true;
    fire($("day_MO"), "change");
    expect($("day_freq_error").classList.contains("d-none")).toBe(true);
  });

  it("also checks the weekdays when the end date changes", () => {
    fire($("recurrence_until"), "change");
    expect($("day_freq_error").classList.contains("d-none")).toBe(false);
  });

  it("does not let a click on the scope radios close the menu", () => {
    const outer = vi.fn();
    $("update_dropdown").addEventListener("click", outer);
    $("update_this").dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(outer).not.toHaveBeenCalled();
  });
});

describe("modal", () => {
  it("asks before closing and cancels the close on 'no'", () => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => false),
    );
    const event = new Event("hide.bs.modal", { cancelable: true });
    $("unavailabilityModal").dispatchEvent(event);
    expect(confirm).toHaveBeenCalledWith(
      "Are you sure you want to exit? All changes will be lost.",
    );
    expect(event.defaultPrevented).toBe(true);
  });

  it("closes a saved dialog without asking", () => {
    vi.stubGlobal("confirm", vi.fn());
    const modal = $("unavailabilityModal");
    modal.dataset.saved = "true";
    const event = new Event("hide.bs.modal", { cancelable: true });
    modal.dispatchEvent(event);
    expect(confirm).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });

  it("lets the close go ahead on 'yes'", () => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => true),
    );
    const event = new Event("hide.bs.modal", { cancelable: true });
    $("unavailabilityModal").dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
  });

  it("resets the form once hidden", () => {
    $("title").value = "x";
    $("all_day_checkbox").checked = true;
    $("end_time_field").disabled = true;
    $("time_error").classList.remove("d-none");
    $("save_button").disabled = true;
    $("recurrence_options").style.display = "block";
    $("delete_forms").style.display = "flex";
    $("calendar_dialog_alert").innerHTML = '<div class="alert">Failed</div>';
    fire($("unavailabilityModal"), "hidden.bs.modal");

    expect($("title").value).toBe("");
    expect($("calendar_dialog_alert").innerHTML).toBe("");
    expect($("all_day_checkbox").checked).toBe(false);
    expect($("end_time_field").disabled).toBe(false);
    expect($("time_error").classList.contains("d-none")).toBe(true);
    expect($("save_button").disabled).toBe(false);
    expect($("recurrence_options").style.display).toBe("none");
    expect($("weekly_options").style.display).toBe("none");
    expect($("delete_forms").style.display).toBe("none");
    expect(collapseHide).toHaveBeenCalled();
  });

  it("proposes the next full Toronto hour, for one hour, when it opens empty", () => {
    fire($("unavailabilityModal"), "show.bs.modal");
    const start = new Date(`${$("start_time_field").value}Z`);
    const end = new Date(`${$("end_time_field").value}Z`);
    expect(start.getUTCMinutes()).toBe(0);
    expect(start.getTime()).toBeGreaterThan(instantToWall(Date.now()));
    expect(end.getTime() - start.getTime()).toBe(3600000);
  });

  it("keeps times that are already filled in when it opens", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    fire($("unavailabilityModal"), "show.bs.modal");
    expect($("start_time_field").value).toBe("2027-03-17T10:00");
  });
});

describe("submit", () => {
  function submit() {
    fire($("unavailForm"), "submit", { cancelable: true });
  }

  it("writes the start and end as the UTC instants of the Toronto times", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    submit();
    expect($("utc_start_time").value).toBe("2027-03-17T14:00:00.000Z");
    expect($("utc_end_time").value).toBe("2027-03-17T15:00:00.000Z");
  });

  it("leaves the rule empty when the entry does not repeat", () => {
    $("recurrence_rule_field").value = "stale";
    $("start_time_field").value = "2027-03-17T10:00";
    submit();
    expect($("recurrence_rule_field").value).toBe("");
  });

  it("builds a weekly rule on the ticked days", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("recurrence_frequency").value = "WEEKLY";
    $("day_MO").checked = true;
    $("day_FR").checked = true;
    submit();
    const rule = $("recurrence_rule_field").value;
    expect(rule).toContain("FREQ=WEEKLY");
    expect(rule).toMatch(/BYDAY=MO,FR/);
    expect(rule).not.toContain("UNTIL");
  });

  it("ends the rule at the end of the chosen Toronto day", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("recurrence_frequency").value = "DAILY";
    $("recurrence_until").value = "2027-03-25";
    submit();
    expect($("recurrence_rule_field").value).toContain(
      "UNTIL=20270326T035959Z",
    );
  });

  it("treats the all-day start as midnight", () => {
    $("start_time_field").value = "2027-03-17T00:00";
    $("end_time_field").value = "2027-03-18T00:00";
    submit();
    expect($("utc_start_time").value).toBe("2027-03-17T04:00:00.000Z");
    expect($("utc_end_time").value).toBe("2027-03-18T04:00:00.000Z");
  });
});

const form = () => document.querySelector("#unavailabilityModal form");

function entry(overrides = {}) {
  return {
    id: "31",
    allDay: false,
    startStr: "2027-03-17T13:00:00-04:00",
    endStr: "2027-03-17T15:00:00-04:00",
    title: "Lecture",
    description: "Calculus",
    occurrenceStart: "2027-03-17T17:00:00Z",
    series: null,
    ...overrides,
  };
}

// What the feed sends of a series' repeat
const weekly = ({ days = ["MO", "WE"], until = "2027-03-31" } = {}) => ({
  frequency: "WEEKLY",
  weekdays: days,
  until,
});
const withFreq = (frequency) => ({ frequency, weekdays: [], until: null });

describe("keeping the series' own times", () => {
  const submit = () => fire($("unavailForm"), "submit", { cancelable: true });

  it("asks the server to keep them when the times are saved as they were filled", () => {
    controller().openForEdit(entry({ series: weekly() }));
    $("title").value = "Renamed";
    submit();
    expect($("keep_series_times").disabled).toBe(false);
    expect($("keep_series_times").value).toBe("1");
  });

  it("does not once a time was changed, nor for a new entry", () => {
    controller().openForEdit(entry({ series: weekly() }));
    $("start_time_field").value = "2027-03-17T14:00";
    submit();
    expect($("keep_series_times").disabled).toBe(true);

    controller().openForEdit(entry({ series: weekly() }));
    $("all_day_checkbox").checked = true;
    submit();
    expect($("keep_series_times").disabled).toBe(true);

    controller().openForAdd();
    submit();
    expect($("keep_series_times").disabled).toBe(true);
  });
});

describe("openForEdit", () => {
  it("opens the modal in edit mode against the unavailability URL", () => {
    controller().openForEdit(entry());

    expect(shown).toEqual(["unavailabilityModal"]);
    expect(form().action).toContain("/staff/unavailabilities/31");
    const method = form().querySelector('input[name="_method"]');
    expect(method.value).toBe("patch");
    expect(method.disabled).toBe(false);
    expect($("unavailabilityModalLabel").textContent).toBe(
      "Edit Unavailability",
    );
    expect($("save_button").value).toBe("Update");
    expect($("title").value).toBe("Lecture");
    expect($("description").value).toBe("Calculus");
    expect($("delete_forms").style.display).toBe("flex");
    expect($("delete_single_form").action).toContain(
      "/staff/unavailabilities/31/delete_with_scope",
    );
    expect($("delete_all_form").action).toContain(
      "/staff/unavailabilities/31/delete_with_scope",
    );
  });

  it("encodes an id with reserved characters in the form and delete actions", () => {
    controller().openForEdit(entry({ id: "a/../b?x#y" }));
    const encoded = "a%2F..%2Fb%3Fx%23y";
    expect(form().getAttribute("action")).toBe(
      `/staff/unavailabilities/${encoded}`,
    );
    expect($("delete_single_form").getAttribute("action")).toBe(
      `/staff/unavailabilities/${encoded}/delete_with_scope`,
    );
    expect($("delete_all_form").getAttribute("action")).toBe(
      `/staff/unavailabilities/${encoded}/delete_with_scope`,
    );
  });

  it("ends an occurrence the calendar gives no end one wall-clock hour after its start", () => {
    controller().openForEdit(
      entry({ startStr: "2027-11-07T01:30:00-04:00", endStr: "" }),
    );
    expect($("start_time_field").value).toBe("2027-11-07T01:30");
    expect($("end_time_field").value).toBe("2027-11-07T02:30");
  });

  it("writes the times in Toronto time", () => {
    controller().openForEdit(entry());
    expect($("start_time_field").value).toBe("2027-03-17T13:00");
    expect($("end_time_field").value).toBe("2027-03-17T15:00");
  });

  it("leaves the end date empty for a repeating entry without one", () => {
    controller().openForEdit(entry({ series: weekly({ until: null }) }));
    expect($("recurrence_until").value).toBe("");
  });

  it("checks all-day, snaps to midnight and locks the end", () => {
    controller().openForEdit(
      entry({ allDay: true, startStr: "2027-03-17", endStr: "2027-03-18" }),
    );
    expect($("all_day_checkbox").checked).toBe(true);
    expect($("end_time_field").disabled).toBe(true);
    expect($("start_time_field").value).toMatch(/^2027-03-17T00:00$/);
    expect($("end_time_field").value).toMatch(/^2027-03-18T00:00$/);
  });

  it("falls back to empty title and description", () => {
    controller().openForEdit(entry({ title: "", description: "" }));
    expect($("title").value).toBe("");
    expect($("description").value).toBe("");
  });

  it("keeps the single save button and hides the delete choices for one-off entries", () => {
    controller().openForEdit(entry());
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect($("delete_following_form").style.display).toBe("none");
    expect($("delete_all_form").style.display).toBe("none");
  });

  it("restores the weekly repeat of a series and moves save into the scope menu", () => {
    controller().openForEdit(entry({ series: weekly() }));

    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("recurrence_until").value).toBe("2027-03-31");
    // saving writes the rule as stored, from the start of the occurrence
    fire($("unavailForm"), "submit", { cancelable: true });
    expect($("recurrence_rule_field").value).toBe(
      "DTSTART;TZID=America/Toronto:20270317T130000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270401T035959Z",
    );
    expect($("update_dropdown_items").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("block");
    expect($("delete_following_form").style.display).toBe("block");
    expect($("delete_all_form").style.display).toBe("block");
  });

  it("ticks the day boxes of the series' weekdays only", () => {
    controller().openForEdit(entry({ series: weekly({ days: ["SU"] }) }));
    controller().openForEdit(entry({ series: weekly() }));
    expect($("day_MO").checked).toBe(true);
    expect($("day_WE").checked).toBe(true);
    expect($("day_TU").checked).toBe(false);
    expect($("day_SU").checked).toBe(false);
  });

  it("restores daily and monthly series, with no day ticked", () => {
    controller().openForEdit(entry({ series: weekly() }));
    controller().openForEdit(entry({ series: withFreq("DAILY") }));
    expect($("recurrence_frequency").value).toBe("DAILY");
    expect($("weekly_options").style.display).toBe("none");
    expect($("day_MO").checked).toBe(false);
    controller().openForEdit(entry({ series: withFreq("MONTHLY") }));
    expect($("recurrence_frequency").value).toBe("MONTHLY");
  });

  it("leaves the frequency empty for a series it has no choice for", () => {
    controller().openForEdit(entry({ series: withFreq("YEARLY") }));
    expect($("recurrence_frequency").value).toBe("");
    expect($("weekly_options").style.display).toBe("none");
  });

  it("turns the method field on and points at the entry when edited again", () => {
    controller().openForEdit(entry());
    controller().openForEdit(entry({ id: "32" }));
    expect(form().querySelectorAll('input[name="_method"]')).toHaveLength(1);
    expect(form().querySelector('input[name="_method"]').disabled).toBe(false);
    expect(form().action).toContain("/staff/unavailabilities/32");
  });

  it("sets the occurrence start the feed sent for every delete form", () => {
    controller().openForEdit(
      entry({ occurrenceStart: "2027-03-17T17:00:00.000Z" }),
    );
    const values = [...document.querySelectorAll(".delete_start_date")].map(
      (i) => i.value,
    );
    expect(values).toEqual([
      "2027-03-17T17:00:00.000Z",
      "2027-03-17T17:00:00.000Z",
    ]);
  });
});

describe("returning focus", () => {
  it("focuses the opening button once the dialog is hidden, and only then", () => {
    const button = document.createElement("button");
    document.body.append(button);
    controller().openForAdd({ returnFocusTo: button });
    expect(document.activeElement).not.toBe(button);
    fire($("unavailabilityModal"), "hidden.bs.modal");
    expect(document.activeElement).toBe(button);

    button.blur();
    controller().openForAdd();
    fire($("unavailabilityModal"), "hidden.bs.modal");
    expect(document.activeElement).not.toBe(button);
  });

  it("does not return focus to a button after the dialog was opened from the calendar", () => {
    const button = document.createElement("button");
    document.body.append(button);
    controller().openForAdd({ returnFocusTo: button });
    controller().openForRange({
      start: "2027-03-17T09:00:00",
      end: "2027-03-17T10:00:00",
    });
    fire($("unavailabilityModal"), "hidden.bs.modal");
    expect(document.activeElement).not.toBe(button);
  });
});

describe("openForAdd", () => {
  it("returns an edit modal to add mode", () => {
    controller().openForEdit(entry({ series: weekly() }));
    controller().openForAdd();

    expect(form().action).toContain("/staff/unavailabilities");
    expect(form().action).not.toContain("/31");
    expect(form().querySelector('input[name="_method"]').disabled).toBe(true);
    expect($("unavailabilityModalLabel").textContent).toBe(
      "Add Unavailability",
    );
    expect($("save_button").value).toBe("Save");
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect(shown).toEqual(["unavailabilityModal", "unavailabilityModal"]);
  });

  it("leaves the repeat fields and delete buttons as the last edit left them", () => {
    controller().openForEdit(entry({ series: weekly() }));
    controller().openForAdd();
    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("delete_forms").style.display).toBe("flex");
  });
});

describe("openForRange", () => {
  it("shows the dialog in add mode and fills the dragged range", () => {
    controller().openForRange({
      start: "2027-03-17T09:00:00-04:00",
      end: "2027-03-17T10:00:00-04:00",
    });
    expect(shown).toEqual(["unavailabilityModal"]);
    expect($("save_button").value).toBe("Save");
    expect($("start_time_field").value).toBe("2027-03-17T09:00");
    expect($("end_time_field").value).toBe("2027-03-17T10:00");
  });
});
