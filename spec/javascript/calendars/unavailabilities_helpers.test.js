// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UNAVAILABILITY_MODAL_HTML } from "./event_modal_fixture.js";

const shown = [];
vi.mock("bootstrap", () => ({
  Modal: class {
    constructor(el) {
      this.el = el;
    }
    show() {
      shown.push(this.el.id);
    }
  },
}));

const { eventClick, addUnavailabilityClick, eventCreate } =
  await import("../../../app/javascript/src/unavailabilities_helpers.js");
const { toLocalDatetimeString } =
  await import("../../../app/javascript/src/calendar_helper.js");

const $ = (id) => document.getElementById(id);
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
              until: new Date(2027, 2, 31, 23, 59, 59),
              ...extra,
            },
          },
        ],
      },
    },
  },
});

beforeEach(() => {
  document.body.innerHTML = UNAVAILABILITY_MODAL_HTML;
  shown.length = 0;
});

describe("eventClick (unavailabilities)", () => {
  it("opens the modal in edit mode against the unavailability URL", () => {
    eventClick(fcEvent());

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

  it("writes the times in the browser's local time", () => {
    eventClick(fcEvent());
    expect($("start_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T13:00:00-04:00")),
    );
    expect($("end_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T15:00:00-04:00")),
    );
  });

  it("checks all-day, snaps to midnight and locks the end", () => {
    eventClick(
      fcEvent({ allDay: true, startStr: "2027-03-17", endStr: "2027-03-18" }),
    );
    expect($("all_day_checkbox").checked).toBe(true);
    expect($("end_time_field").disabled).toBe(true);
    expect($("start_time_field").value).toMatch(/^2027-03-17T00:00$/);
    expect($("end_time_field").value).toMatch(/^2027-03-18T00:00$/);
  });

  it("falls back to empty title and description", () => {
    eventClick(fcEvent({ def: { title: "", extendedProps: {} } }));
    expect($("title").value).toBe("");
    expect($("description").value).toBe("");
  });

  it("keeps the single save button and hides the delete choices for one-off entries", () => {
    eventClick(fcEvent());
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
    expect($("delete_following_form").style.display).toBe("none");
    expect($("delete_all_form").style.display).toBe("none");
  });

  it("restores the weekly rule of a repeating entry and moves save into the scope menu", () => {
    eventClick(fcEvent({ def: weeklyDef() }));

    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("recurrence_until").value).toBe("2027-03-31");
    expect($("recurrence_rule_field").value).toContain("FREQ=WEEKLY");
    expect($("update_dropdown_items").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("block");
    expect($("delete_following_form").style.display).toBe("block");
    expect($("delete_all_form").style.display).toBe("block");
  });

  it("ticks the day box one place after the rule's weekday number", () => {
    // rrule numbers Monday 0 and Wednesday 2; the boxes run Sunday first, so
    // the page ticks Monday and Wednesday as index+1
    eventClick(fcEvent({ def: weeklyDef({ byweekday: [0, 2] }) }));
    expect($("day_MO").checked).toBe(true);
    expect($("day_WE").checked).toBe(true);
    expect($("day_TU").checked).toBe(false);
  });

  it("ticks Sunday for a rule on Sunday (weekday 6)", () => {
    eventClick(fcEvent({ def: weeklyDef({ byweekday: [6] }) }));
    expect($("day_SU").checked).toBe(true);
  });

  it("restores daily and monthly rules", () => {
    eventClick(fcEvent({ def: weeklyDef({ freq: 3, byweekday: undefined }) }));
    expect($("recurrence_frequency").value).toBe("DAILY");
    expect($("weekly_options").style.display).toBe("none");
    eventClick(fcEvent({ def: weeklyDef({ freq: 1, byweekday: undefined }) }));
    expect($("recurrence_frequency").value).toBe("MONTHLY");
  });

  it("sets the start date for every delete form", () => {
    eventClick(fcEvent());
    const values = [...document.querySelectorAll(".delete_start_date")].map(
      (i) => i.value,
    );
    expect(values).toEqual([
      "2027-03-17T17:00:00.000Z",
      "2027-03-17T17:00:00.000Z",
    ]);
  });
});

describe("addUnavailabilityClick", () => {
  it("returns an edit modal to add mode", () => {
    eventClick(fcEvent({ def: weeklyDef() }));
    addUnavailabilityClick();

    expect(form().action).toContain("/staff/unavailabilities");
    expect(form().action).not.toContain("/31");
    expect(form().querySelector('input[name="_method"]')).toBeNull();
    expect($("unavailabilityModalLabel").textContent).toBe(
      "Add Unavailability",
    );
    expect($("save_button").value).toBe("Save");
    expect($("modal_buttons").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
  });

  it("leaves the repeat fields and delete buttons as the last edit left them", () => {
    eventClick(fcEvent({ def: weeklyDef() }));
    addUnavailabilityClick();
    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("delete_forms").style.display).toBe("flex");
  });
});

describe("eventCreate (unavailabilities)", () => {
  it("clicks the add button, then fills the dragged range", () => {
    const click = vi.fn();
    $("addUnavailabilityButton").addEventListener("click", click);
    eventCreate({
      startStr: "2027-03-17T09:00:00-04:00",
      endStr: "2027-03-17T10:00:00-04:00",
    });
    expect(click).toHaveBeenCalledTimes(1);
    expect($("save_button").value).toBe("Save");
    expect($("start_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T09:00:00-04:00")),
    );
    expect($("end_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T10:00:00-04:00")),
    );
  });
});
