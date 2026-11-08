// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UNAVAILABILITY_MODAL_HTML } from "./event_modal_fixture.js";

const collapseHide = vi.fn();
vi.mock("bootstrap", () => ({
  Modal: class {},
  Collapse: class {
    hide() {
      collapseHide();
    }
  },
}));

await import("../../../app/javascript/src/manage_unavailabilities.js");
const { toLocalDatetimeString } =
  await import("../../../app/javascript/src/calendar_helper.js");

const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));

function setStart(local) {
  $("start_time_field").value = local;
  fire($("start_time_field"), "change");
}

beforeEach(() => {
  document.body.innerHTML = UNAVAILABILITY_MODAL_HTML;
  collapseHide.mockClear();
  document.dispatchEvent(new Event("turbo:load"));
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

  it("proposes the next full hour, for one hour, when it opens empty", () => {
    fire($("unavailabilityModal"), "show.bs.modal");
    const start = new Date($("start_time_field").value);
    const end = new Date($("end_time_field").value);
    expect(start.getMinutes()).toBe(0);
    expect(start.getTime()).toBeGreaterThan(Date.now());
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

  it("writes the start and end as UTC instants", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("end_time_field").value = "2027-03-17T11:00";
    submit();
    expect($("utc_start_time").value).toBe(
      new Date("2027-03-17T10:00").toISOString(),
    );
    expect($("utc_end_time").value).toBe(
      new Date("2027-03-17T11:00").toISOString(),
    );
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

  it("ends the rule at the end of the chosen day", () => {
    $("start_time_field").value = "2027-03-17T10:00";
    $("recurrence_frequency").value = "DAILY";
    $("recurrence_until").value = "2027-03-25";
    submit();
    const until = $("recurrence_rule_field").value.match(/UNTIL=(\w+)/)[1];
    expect(until).toMatch(/^20270325T|^20270326T/);
  });

  it("treats the all-day start as midnight", () => {
    $("start_time_field").value = "2027-03-17T00:00";
    $("end_time_field").value = "2027-03-18T00:00";
    submit();
    expect(toLocalDatetimeString(new Date($("utc_end_time").value))).toBe(
      "2027-03-18T00:00",
    );
  });
});
