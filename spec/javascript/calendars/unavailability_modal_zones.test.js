// @vitest-environment happy-dom
// The staff unavailability modal reads and writes Toronto wall-clock times,
// like the calendar it opens from. Every example runs with the browser clock
// in Toronto, in UTC and in Tokyo. The cases come from
// spec/fixtures/calendar_dst_cases.json, which the request specs also read.
import {
  afterAll,
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";
import { Application } from "@hotwired/stimulus";
import cases from "../../fixtures/calendar_dst_cases.json";
import { UNAVAILABILITY_MODAL_HTML } from "./event_modal_fixture.js";

vi.mock("bootstrap", () => ({
  Modal: class {
    static getOrCreateInstance() {
      return { show() {} };
    }
  },
  Collapse: class {
    hide() {}
  },
}));

const { default: UnavailabilityForm } =
  await import("../../../app/javascript/controllers/unavailability_form_controller.js");

let application;
const controller = () =>
  application.getControllerForElementAndIdentifier(
    document.getElementById("unavailabilityModal"),
    "unavailability-form",
  );
const openForEdit = (event) => controller().openForEdit(event);
const openForRange = (range) => controller().openForRange(range);
const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));
const submit = () => fire($("unavailForm"), "submit", { cancelable: true });
const hasOffset = (value) => /(Z|[+-]\d{2}:\d{2})$/.test(value);

// Offset of each zone on 2027-03-17, in minutes as getTimezoneOffset reports it
const ZONES = { "America/Toronto": 240, UTC: 0, "Asia/Tokyo": -540 };
const originalZone = process.env.TZ;
afterAll(() => {
  vi.useRealTimers();
  if (originalZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalZone;
});

function openNew(start, end = start) {
  $("start_time_field").value = start;
  $("end_time_field").value = end;
}

function entry(start, { occurrenceStart = null, series = null } = {}) {
  return {
    id: 31,
    allDay: false,
    startStr: start,
    endStr: start,
    title: "Lecture",
    description: "",
    occurrenceStart,
    series,
  };
}

describe.each(Object.entries(ZONES))(
  "with the browser clock in %s",
  (zone, offsetOn17March) => {
    beforeEach(async () => {
      process.env.TZ = zone;
      document.body.innerHTML = UNAVAILABILITY_MODAL_HTML;
      application = Application.start();
      application.register("unavailability-form", UnavailabilityForm);
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    afterEach(() => {
      application.stop();
      document.body.innerHTML = "";
    });

    it("has that zone", () => {
      expect(new Date(2027, 2, 17, 12).getTimezoneOffset()).toBe(
        offsetOn17March,
      );
    });

    describe("saving sends the instant of the Toronto time in the field", () => {
      for (const c of cases.fieldToInstant) {
        it(c.label, () => {
          openNew(c.field);
          submit();
          expect($("utc_start_time").value).toBe(c.instant);
          expect($("utc_end_time").value).toBe(c.instant);
        });
      }
    });

    describe("saving a repeating series writes its start in Toronto time", () => {
      for (const c of cases.fieldToInstant) {
        it(c.label, () => {
          openNew(c.field);
          $("recurrence_frequency").value = "DAILY";
          submit();
          expect($("recurrence_rule_field").value).toBe(
            `${c.storedStart}\nRRULE:FREQ=DAILY`,
          );
        });
      }
    });

    describe("a repeat end date ends the series at the end of that Toronto day", () => {
      for (const c of cases.untilDates) {
        it(c.label, () => {
          openNew("2027-03-10T10:00", "2027-03-10T11:00");
          $("recurrence_frequency").value = "DAILY";
          $("recurrence_until").value = c.date;
          submit();
          expect($("recurrence_rule_field").value).toContain(
            `UNTIL=${c.until}`,
          );
        });
      }
    });

    describe("opening an unavailability from the calendar", () => {
      for (const c of cases.calendarStrings) {
        it(`shows ${c.label} at its Toronto time`, () => {
          openForEdit(entry(c.start));
          expect($("start_time_field").value).toBe(c.field);
        });

        it(`deletes ${c.label} by the occurrence start the feed sent`, () => {
          openForEdit(entry(c.start, { occurrenceStart: c.instant }));
          const sent = [...document.querySelectorAll(".delete_start_date")];
          expect(sent.map((input) => input.value)).toEqual([
            c.instant,
            c.instant,
          ]);
        });
      }

      // The server sends the Toronto date a series repeats until (see
      // RecurrenceRule#dialog_fields); the field shows it as it is.
      it("shows the repeat end date the feed sends", () => {
        openForEdit(
          entry("2027-03-10T10:00:00", {
            series: { frequency: "DAILY", weekdays: [], until: "2027-03-14" },
          }),
        );
        expect($("recurrence_until").value).toBe("2027-03-14");
      });
    });

    describe("selecting a range on the calendar", () => {
      for (const c of cases.calendarStrings.filter(
        (c) => !hasOffset(c.start),
      )) {
        it(`fills ${c.label} at its Toronto time`, () => {
          openForRange({ start: c.start, end: c.start });
          expect($("start_time_field").value).toBe(c.field);
        });
      }
    });

    describe("the form", () => {
      it("makes an all-day entry on the day the clocks go forward Toronto midnight to midnight", () => {
        openNew("2027-03-14T10:30", "2027-03-14T11:30");
        $("all_day_checkbox").checked = true;
        fire($("all_day_checkbox"), "change");
        expect($("start_time_field").value).toBe("2027-03-14T00:00");
        expect($("end_time_field").value).toBe("2027-03-15T00:00");
      });

      it("saves that all-day entry as the 23 hours of the Toronto day", () => {
        openNew("2027-03-14T10:30", "2027-03-14T11:30");
        $("all_day_checkbox").checked = true;
        fire($("all_day_checkbox"), "change");
        submit();
        expect($("utc_start_time").value).toBe("2027-03-14T05:00:00.000Z");
        expect($("utc_end_time").value).toBe("2027-03-15T04:00:00.000Z");
      });

      it("ends an entry that is no longer all-day one hour after its start", () => {
        $("all_day_checkbox").checked = false;
        openNew("2027-03-14T01:30");
        fire($("all_day_checkbox"), "change");
        expect($("end_time_field").value).toBe("2027-03-14T03:30");
      });

      it("ticks the Toronto weekday of the start for a weekly entry", () => {
        openNew("2027-03-17T22:30", "2027-03-17T23:00");
        $("recurrence_frequency").value = "WEEKLY";
        fire($("recurrence_frequency"), "change");
        const ticked = [...document.querySelectorAll(".dayCheckbox")]
          .filter((cb) => cb.checked)
          .map((cb) => cb.value);
        expect(ticked).toEqual(["WE"]);
      });

      it("proposes the next whole Toronto hour when the modal opens", () => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date("2027-03-17T13:20:00Z"));
        try {
          fire($("unavailabilityModal"), "show.bs.modal");
          expect($("start_time_field").value).toBe("2027-03-17T10:00");
          expect($("end_time_field").value).toBe("2027-03-17T11:00");
        } finally {
          vi.useRealTimers();
        }
      });
    });
  },
);
