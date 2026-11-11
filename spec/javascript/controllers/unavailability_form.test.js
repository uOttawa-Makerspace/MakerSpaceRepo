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
    fire($("unavailabilityModal"), "hidden.bs.modal");

    expect($("title").value).toBe("");
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

function fcEvent(overrides = {}) {
  const { def = {}, ...rest } = overrides;
  return {
    id: "31",
    allDay: false,
    startStr: "2027-03-17T13:00:00-04:00",
    endStr: "2027-03-17T15:00:00-04:00",
    _def: {
      title: "Lecture",
      extendedProps: { description: "Calculus" },
      ...def,
    },
    ...rest,
  };
}

const weeklyDef = (extra = {}) => ({
  recurringDef: {
    typeData: {
      rruleSet: {
        _rrule: [
          {
            origOptions: {
              freq: 2,
              dtstart: new Date(Date.UTC(2027, 2, 15, 14)),
              byweekday: [0, 2],
              until: new Date(Date.UTC(2027, 2, 31, 23, 59, 59)),
              ...extra,
            },
          },
        ],
      },
    },
  },
});

describe("openForEdit", () => {
  it("opens the modal in edit mode against the unavailability URL", () => {
    controller().openForEdit(fcEvent());

    expect(shown).toEqual(["unavailabilityModal"]);
    expect(form().action).toContain("/staff/unavailabilities/31");
    expect(form().querySelector('input[name="_method"]').value).toBe("patch");
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

  it("writes the times in Toronto time", () => {
    controller().openForEdit(fcEvent());
    expect($("start_time_field").value).toBe("2027-03-17T13:00");
    expect($("end_time_field").value).toBe("2027-03-17T15:00");
  });

  it("leaves the end date empty for a repeating entry without one", () => {
    controller().openForEdit(fcEvent({ def: weeklyDef({ until: null }) }));
    expect($("recurrence_until").value).toBe("");
  });

  it("checks all-day, snaps to midnight and locks the end", () => {
    controller().openForEdit(
      fcEvent({ allDay: true, startStr: "2027-03-17", endStr: "2027-03-18" }),
    );
    expect($("all_day_checkbox").checked).toBe(true);
    expect($("end_time_field").disabled).toBe(true);
    expect($("start_time_field").value).toMatch(/^2027-03-17T00:00$/);
    expect($("end_time_field").value).toMatch(/^2027-03-18T00:00$/);
  });

  it("falls back to empty title and description", () => {
    controller().openForEdit(
      fcEvent({ def: { title: "", extendedProps: {} } }),
    );
    expect($("title").value).toBe("");
    expect($("description").value).toBe("");
  });

  it("keeps the single save button and hides the delete choices for one-off entries", () => {
    controller().openForEdit(fcEvent());
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect($("delete_following_form").style.display).toBe("none");
    expect($("delete_all_form").style.display).toBe("none");
  });

  it("restores the weekly rule of a repeating entry and moves save into the scope menu", () => {
    controller().openForEdit(fcEvent({ def: weeklyDef() }));

    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("recurrence_until").value).toBe("2027-03-31");
    // the feed gives Toronto wall times; the field holds the rule as stored
    expect($("recurrence_rule_field").value).toBe(
      "DTSTART;TZID=America/Toronto:20270315T140000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20270401T035959Z",
    );
    expect($("update_dropdown_items").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("block");
    expect($("delete_following_form").style.display).toBe("block");
    expect($("delete_all_form").style.display).toBe("block");
  });

  it("ticks the day box one place after the rule's weekday number", () => {
    // rrule numbers Monday 0 and Wednesday 2; the boxes run Sunday first, so
    // the page ticks Monday and Wednesday as index+1
    controller().openForEdit(
      fcEvent({ def: weeklyDef({ byweekday: [0, 2] }) }),
    );
    expect($("day_MO").checked).toBe(true);
    expect($("day_WE").checked).toBe(true);
    expect($("day_TU").checked).toBe(false);
  });

  it("ticks Sunday for a rule on Sunday (weekday 6)", () => {
    controller().openForEdit(fcEvent({ def: weeklyDef({ byweekday: [6] }) }));
    expect($("day_SU").checked).toBe(true);
  });

  it("restores daily and monthly rules", () => {
    controller().openForEdit(
      fcEvent({ def: weeklyDef({ freq: 3, byweekday: undefined }) }),
    );
    expect($("recurrence_frequency").value).toBe("DAILY");
    expect($("weekly_options").style.display).toBe("none");
    controller().openForEdit(
      fcEvent({ def: weeklyDef({ freq: 1, byweekday: undefined }) }),
    );
    expect($("recurrence_frequency").value).toBe("MONTHLY");
  });

  it("leaves the frequency alone for a rule it has no choice for", () => {
    controller().openForEdit(
      fcEvent({ def: weeklyDef({ freq: 0, byweekday: undefined }) }),
    );
    expect($("recurrence_frequency").value).toBe("");
    expect($("weekly_options").style.display).toBe("none");
  });

  it("keeps a single method field when edited again", () => {
    controller().openForEdit(fcEvent());
    controller().openForEdit(fcEvent({ id: "32" }));
    expect(form().querySelectorAll('input[name="_method"]')).toHaveLength(1);
    expect(form().action).toContain("/staff/unavailabilities/32");
  });

  it("sets the start date for every delete form", () => {
    controller().openForEdit(fcEvent());
    const values = [...document.querySelectorAll(".delete_start_date")].map(
      (i) => i.value,
    );
    expect(values).toEqual([
      "2027-03-17T17:00:00.000Z",
      "2027-03-17T17:00:00.000Z",
    ]);
  });
});

describe("openForAdd", () => {
  it("returns an edit modal to add mode", () => {
    controller().openForEdit(fcEvent({ def: weeklyDef() }));
    controller().openForAdd();

    expect(form().action).toContain("/staff/unavailabilities");
    expect(form().action).not.toContain("/31");
    expect(form().querySelector('input[name="_method"]')).toBeNull();
    expect($("unavailabilityModalLabel").textContent).toBe(
      "Add Unavailability",
    );
    expect($("save_button").value).toBe("Save");
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect(shown).toEqual(["unavailabilityModal", "unavailabilityModal"]);
  });

  it("leaves the repeat fields and delete buttons as the last edit left them", () => {
    controller().openForEdit(fcEvent({ def: weeklyDef() }));
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
