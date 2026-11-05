// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EVENT_MODAL_HTML } from "./event_modal_fixture.js";

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

const { addEventClick, eventClick, eventCreate, toLocalDatetimeString } =
  await import("../../../app/javascript/src/calendar_helper.js");

const $ = (id) => document.getElementById(id);
const form = () => document.querySelector("#eventModal form");

// A FullCalendar EventImpl reduced to what eventClick reads.
function fcEvent(overrides = {}) {
  const { props = {}, def = {}, ...rest } = overrides;
  return {
    id: "event-12",
    allDay: false,
    startStr: "2027-03-17T10:00:00-04:00",
    endStr: "2027-03-17T11:30:00-04:00",
    end: new Date("2027-03-17T11:30:00-04:00"),
    _def: {
      title: "✎ Team sync",
      extendedProps: { eventType: "meeting", ...props },
      ...def,
    },
    ...rest,
  };
}

beforeEach(() => {
  document.body.innerHTML = EVENT_MODAL_HTML;
  shown.length = 0;
  vi.restoreAllMocks();
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => [] })),
  );
});

describe("addEventClick", () => {
  it("resets a modal that was left in edit mode", () => {
    $("title").value = "old";
    $("description").value = "old text";
    form().action = "/admin/events/5";
    const method = document.createElement("input");
    method.name = "_method";
    form().appendChild(method);
    $("recurrence_frequency").value = "DAILY";
    $("recurrence_options").style.display = "block";
    $("day_MO").checked = true;
    $("all_day_checkbox").checked = true;
    $("end_time_field").disabled = true;
    $("eventModalLabel").textContent = "Edit Event";
    $("save_button").value = "Update";

    addEventClick();

    expect($("title").value).toBe("");
    expect($("description").value).toBe("");
    expect(form().action).toContain("/admin/events");
    expect(form().action).not.toContain("/admin/events/5");
    expect(form().querySelector('input[name="_method"]')).toBeNull();
    expect($("recurrence_frequency").value).toBe("");
    expect($("recurrence_options").style.display).toBe("none");
    expect($("day_MO").checked).toBe(false);
    expect($("all_day_checkbox").checked).toBe(false);
    expect($("end_time_field").disabled).toBe(false);
    expect($("eventModalLabel").textContent).toBe("Add Event");
    expect($("save_button").value).toBe("Save Draft");
    expect($("publish_and_delete_forms").style.display).toBe("none");
  });

  it("moves the save button back out of the scope menu", () => {
    $("dropdown_save_button_container").appendChild($("save_button"));
    addEventClick();
    expect($("save_button_container").contains($("save_button"))).toBe(true);
    expect($("update_dropdown").style.display).toBe("none");
  });

  it("names the fields for an event and makes the staff select multiple", () => {
    addEventClick();
    expect($("title").name).toBe("event[title]");
    expect($("start_time_field").name).toBe("event[utc_start_time]");
    expect($("end_time_field").name).toBe("event[utc_end_time]");
    expect($("recurrence_rule_field").name).toBe("event[recurrence_rule]");
    expect($("staff_select").name).toBe("staff_select[]");
    expect($("staff_select").hasAttribute("multiple")).toBe(true);
    expect(
      document.querySelector("#eventModal input[type=hidden][value='7']").name,
    ).toBe("event[space_id]");
  });

  it("fills the staff list from the server once, when it is empty", async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => [
        { id: 1, name: "Ada" },
        { id: 2, name: "Wanda" },
      ],
    });
    addEventClick();
    await vi.waitFor(() => expect($("staff_select").options.length).toBe(2));
    expect(fetch).toHaveBeenCalledWith("/admin/calendar/staff_json/7");
    expect([...$("staff_select").options].map((o) => o.textContent)).toEqual([
      "Ada",
      "Wanda",
    ]);
  });

  it("leaves the staff list empty when the server answers with an error", async () => {
    fetch.mockResolvedValueOnce({ ok: false, json: async () => [] });
    addEventClick();
    await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
    expect($("staff_select").options.length).toBe(0);
  });

  it("logs the failure when the staff request throws", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    fetch.mockRejectedValueOnce(new Error("offline"));
    addEventClick();
    await vi.waitFor(() => expect(log).toHaveBeenCalled());
    expect(log.mock.calls[0][0]).toBe("Error fetching staff data:");
  });

  it("takes the space from the form's own field when the page has no space picker", async () => {
    $("space_id").remove();
    addEventClick();
    await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(fetch).toHaveBeenCalledWith("/admin/calendar/staff_json/7");
  });

  it("does not ask for staff when no space field exists at all", async () => {
    $("space_id").remove();
    document.querySelector('input[name="event[space_id]"]').remove();
    addEventClick();
    await Promise.resolve();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("points the form at unavailabilities when that type is chosen, and back", () => {
    addEventClick();
    $("event_type_select").value = "unavailability";
    $("event_type_select").dispatchEvent(new Event("change"));
    expect(form().action).toContain("/staff/unavailabilities");
    expect($("title").name).toBe("staff_unavailability[title]");
    expect($("staff_select").name).toBe("staff_unavailability[user_id]");
    expect($("staff_select").hasAttribute("multiple")).toBe(false);

    $("event_type_select").value = "meeting";
    $("event_type_select").dispatchEvent(new Event("change"));
    expect(form().action).toContain("/admin/events");
    expect($("title").name).toBe("event[title]");
    expect($("staff_select").hasAttribute("multiple")).toBe(true);
  });

  it("shows the training fields only for the training type", () => {
    addEventClick();
    $("event_type_select").value = "training";
    $("event_type_select").dispatchEvent(new Event("change"));
    expect($("training-fields").style.display).toBe("block");
    $("event_type_select").value = "other";
    $("event_type_select").dispatchEvent(new Event("change"));
    expect($("training-fields").style.display).toBe("none");
  });

  it("keeps the edit URL when the type changes during an edit", () => {
    eventClick(fcEvent());
    $("event_type_select").value = "other";
    $("event_type_select").dispatchEvent(new Event("change"));
    expect(form().action).toContain("/admin/events/12");
  });
});

describe("eventClick", () => {
  it("ignores an event without a type", () => {
    eventClick(fcEvent({ props: { eventType: undefined } }));
    expect(shown).toEqual([]);
    expect($("eventModalLabel").textContent).toBe("Add Event");
  });

  it("opens the modal in edit mode for an event", () => {
    eventClick(fcEvent({ props: { description: "Weekly" } }));

    expect(shown).toEqual(["eventModal"]);
    expect($("eventModalLabel").textContent).toBe("Edit Event");
    expect(form().action).toContain("/admin/events/12");
    expect(form().querySelector('input[name="_method"]').value).toBe("patch");
    expect($("title").value).toBe("Team sync");
    expect($("description").value).toBe("Weekly");
    expect($("event_type_select").value).toBe("meeting");
    expect($("event_type_select").disabled).toBe(false);
    expect($("save_button").value).toBe("Update");
    expect($("publish_and_delete_forms").style.display).toBe("flex");
    expect($("delete_single_form").action).toContain(
      "/admin/events/12/delete_with_scope",
    );
    expect($("delete_following_form").style.display).toBe("none");
    expect($("delete_all_form").style.display).toBe("none");
  });

  it("writes the start and end in the browser's local time", () => {
    eventClick(fcEvent());
    expect($("start_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T10:00:00-04:00")),
    );
    expect($("end_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T11:30:00-04:00")),
    );
    expect($("end_time_field").disabled).toBe(false);
    expect($("all_day_checkbox").checked).toBe(false);
  });

  it("defaults the end to one hour after the start when the event has none", () => {
    eventClick(fcEvent({ end: null, endStr: "" }));
    const start = new Date("2027-03-17T10:00:00-04:00");
    expect($("end_time_field").value).toBe(
      toLocalDatetimeString(new Date(start.getTime() + 3600000)),
    );
  });

  it("checks all-day and locks the end field", () => {
    eventClick(
      fcEvent({
        allDay: true,
        startStr: "2027-03-17",
        endStr: "2027-03-18",
        end: new Date("2027-03-18T00:00:00"),
      }),
    );
    expect($("all_day_checkbox").checked).toBe(true);
    expect($("end_time_field").disabled).toBe(true);
    expect($("start_time_field").value).toMatch(/^2027-03-17T/);
  });

  it("gives an all-day event without an end a one-day span", () => {
    eventClick(
      fcEvent({ allDay: true, startStr: "2027-03-17", end: null, endStr: "" }),
    );
    expect($("end_time_field").value).toMatch(/^2027-03-18T/);
  });

  it("fills the training fields", () => {
    eventClick(
      fcEvent({
        props: {
          eventType: "training",
          // strings: happy-dom does not coerce numbers when assigning a select value
          trainingId: "3",
          language: "en",
          course_name: { id: "9" },
        },
      }),
    );
    expect($("training-fields").style.display).toBe("block");
    expect($("training_select").value).toBe("3");
    expect($("language_select").value).toBe("en");
    expect($("course_select").value).toBe("9");
  });

  it("lists the assigned staff as selected options", () => {
    eventClick(
      fcEvent({
        props: {
          assignedUsers: [
            { id: 4, name: "Wanda" },
            { id: 0, name: "Unassigned" },
          ],
        },
      }),
    );
    const options = [...$("staff_select").options];
    expect(options.map((o) => [o.value, o.textContent, o.selected])).toEqual([
      ["4", "Wanda", true],
      ["0", "Unassigned", true],
    ]);
    expect($("staff_select").name).toBe("staff_select[]");
  });

  it("offers to publish a draft and hides the button otherwise", () => {
    eventClick(fcEvent({ props: { draft: true } }));
    expect($("publish_form").style.display).toBe("block");
    expect($("publish_form").action).toContain("/admin/events/12/publish");
    eventClick(fcEvent({ props: { draft: false } }));
    expect($("publish_form").style.display).toBe("none");
  });

  it("restores a repeat rule from the series definition of the calendar", () => {
    const origOptions = {
      freq: 2,
      dtstart: new Date(Date.UTC(2027, 2, 15, 14)),
      byweekday: [0, 2],
      until: new Date(2027, 2, 31, 23, 59, 59),
    };
    eventClick(
      fcEvent({
        def: {
          recurringDef: {
            typeData: { rruleSet: { _rrule: [{ origOptions }] } },
          },
        },
      }),
    );
    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("recurrence_options").style.display).toBe("block");
    expect($("weekly_options").style.display).toBe("block");
    expect($("day_MO").checked).toBe(true);
    expect($("day_WE").checked).toBe(true);
    expect($("day_TU").checked).toBe(false);
    expect($("recurrence_until").value).toBe("2027-03-31");
    expect($("recurrence_rule_field").value).toContain("FREQ=WEEKLY");
    expect($("delete_following_form").style.display).toBe("block");
    expect($("delete_all_form").style.display).toBe("block");
    expect($("update_dropdown").style.display).toBe("block");
    expect($("dropdown_save_button_container").contains($("save_button"))).toBe(
      true,
    );
  });

  it("restores a daily and a monthly rule", () => {
    const rule = (freq) => ({
      def: {
        recurringDef: {
          typeData: {
            rruleSet: {
              _rrule: [
                {
                  origOptions: {
                    freq,
                    dtstart: new Date(Date.UTC(2027, 2, 15)),
                  },
                },
              ],
            },
          },
        },
      },
    });
    eventClick(fcEvent(rule(3)));
    expect($("recurrence_frequency").value).toBe("DAILY");
    expect($("weekly_options").style.display).toBe("none");
    eventClick(fcEvent(rule(1)));
    expect($("recurrence_frequency").value).toBe("MONTHLY");
  });

  it("restores a repeat rule from a rule string, with or without the prefix", () => {
    eventClick(fcEvent({ props: { rrule: "RRULE:FREQ=DAILY" } }));
    expect($("recurrence_frequency").value).toBe("DAILY");
    eventClick(fcEvent({ props: { rrule: "FREQ=WEEKLY;BYDAY=FR" } }));
    expect($("recurrence_frequency").value).toBe("WEEKLY");
    expect($("day_FR").checked).toBe(true);
  });

  it("cannot read a rule string that starts with a start date", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    eventClick(
      fcEvent({
        props: { rrule: "DTSTART:20270315T140000Z\nRRULE:FREQ=DAILY" },
      }),
    );
    expect(log).toHaveBeenCalledWith("RRule parse error", expect.anything());
    expect($("recurrence_frequency").value).toBe("");
  });

  it("logs and carries on when the rule string cannot be read", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    eventClick(fcEvent({ props: { rrule: "RRULE:FREQ=NEVER" } }));
    expect(log).toHaveBeenCalledWith("RRule parse error", expect.anything());
    expect(shown).toEqual(["eventModal"]);
    expect($("recurrence_frequency").value).toBe("");
  });

  it("sets the date every delete form sends", () => {
    eventClick(fcEvent());
    const values = [...document.querySelectorAll(".delete_start_date")].map(
      (i) => i.value,
    );
    expect(values).toEqual([
      "2027-03-17T14:00:00.000Z",
      "2027-03-17T14:00:00.000Z",
    ]);
  });

  it("opens an unavailability with the type locked, its own URLs and its owner", () => {
    eventClick(
      fcEvent({
        id: "31",
        props: {
          eventType: "unavailability",
          userId: 4,
          name: "Wanda Worker (Admin)",
          draft: true,
        },
      }),
    );
    expect($("eventModalLabel").textContent).toBe("Edit Unavailability");
    expect(form().action).toContain("/staff/unavailabilities/31");
    expect($("event_type_select").value).toBe("unavailability");
    expect($("event_type_select").disabled).toBe(true);
    expect(document.querySelector(".lock-indicator").textContent).toContain(
      "cannot be changed",
    );
    expect(
      form().querySelector('input[name="staff_unavailability[event_type]"]')
        .value,
    ).toBe("unavailability");
    expect($("title").name).toBe("staff_unavailability[title]");
    expect($("staff_select").name).toBe("staff_unavailability[user_id]");
    expect($("staff_select").hasAttribute("multiple")).toBe(false);
    expect(
      [...$("staff_select").options].map((o) => [o.value, o.textContent]),
    ).toEqual([["4", "Wanda Worker"]]);
    expect($("publish_form").style.display).toBe("none");
    expect($("delete_single_form").action).toContain(
      "/staff/unavailabilities/31/delete_with_scope",
    );
  });

  it("falls back to 'User' when the unavailability has no owner name", () => {
    eventClick(
      fcEvent({ id: "31", props: { eventType: "unavailability", userId: 4 } }),
    );
    expect($("staff_select").options[0].textContent).toBe("User");
  });

  it("removes the lock again when the next modal is opened for a new event", () => {
    eventClick(
      fcEvent({ id: "31", props: { eventType: "unavailability", userId: 4 } }),
    );
    addEventClick();
    expect($("event_type_select").disabled).toBe(false);
    expect(document.querySelector(".lock-indicator")).toBeNull();
    expect(
      form().querySelector('input[name="staff_unavailability[event_type]"]'),
    ).toBeNull();
  });
});

describe("eventCreate", () => {
  it("copies the dragged range into the form, clicks the add button and resets", () => {
    const click = vi.fn();
    $("addEventButton").addEventListener("click", click);
    eventCreate({
      startStr: "2027-03-17T10:00:00-04:00",
      endStr: "2027-03-17T12:00:00-04:00",
    });

    expect(click).toHaveBeenCalledTimes(1);
    // the reset that follows the click leaves the dragged times in place
    expect($("start_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T10:00:00-04:00")),
    );
    expect($("end_time_field").value).toBe(
      toLocalDatetimeString(new Date("2027-03-17T12:00:00-04:00")),
    );
    expect($("save_button").value).toBe("Save Draft");
  });
});
