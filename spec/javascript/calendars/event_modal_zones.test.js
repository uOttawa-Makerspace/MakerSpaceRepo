// @vitest-environment happy-dom
// The admin event modal reads and writes Toronto wall-clock times, like the
// calendar it opens from. Every example runs with the browser clock in
// Toronto, in UTC and in Tokyo. The cases come from
// spec/fixtures/calendar_dst_cases.json, which the request specs also read.
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import cases from "../../fixtures/calendar_dst_cases.json";
import { EVENT_MODAL_HTML } from "./event_modal_fixture.js";

vi.mock("bootstrap", () => ({
  Modal: class {
    show() {}
  },
  Collapse: class {
    hide() {}
  },
}));
vi.mock("tom-select", () => ({
  default: class {
    on() {}
    sync() {}
    clearOptions() {}
    addOption() {}
    refreshOptions() {}
    destroy() {}
    setTextboxValue() {}
  },
}));

await import("../../../app/javascript/src/manage_calendar_events.js");
const { eventClick, eventCreate } =
  await import("../../../app/javascript/src/calendar_helper.js");

const $ = (id) => document.getElementById(id);
const fire = (el, type, init) => el.dispatchEvent(new Event(type, init));
const submit = () => fire($("eventForm"), "submit", { cancelable: true });
const stampToDate = (stamp) =>
  new Date(
    stamp.replace(
      /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?/,
      "$1-$2-$3T$4:$5:$6Z",
    ),
  );
const hasOffset = (value) => /(Z|[+-]\d{2}:\d{2})$/.test(value);

// Offset of each zone on 2027-03-17, in minutes as getTimezoneOffset reports it
const ZONES = { "America/Toronto": 240, UTC: 0, "Asia/Tokyo": -540 };
const originalZone = process.env.TZ;
afterAll(() => {
  vi.useRealTimers();
  if (originalZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalZone;
});

async function load() {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => [] })),
  );
  document.dispatchEvent(new Event("turbo:load"));
  await vi.waitFor(() => expect($("eventModal").dataset.ready).toBe("true"));
}

async function openNew(start, end = start) {
  await load();
  $("start_time_field").value = start;
  $("end_time_field").value = end;
  fire($("eventModal"), "show.bs.modal");
}

function fcEvent(start, extra = {}) {
  return {
    id: "event-12",
    allDay: false,
    startStr: start,
    endStr: start,
    end: new Date(0),
    _def: { title: "Open lab", extendedProps: { eventType: "other" } },
    ...extra,
  };
}

function dailyUntil(stamp) {
  return {
    recurringDef: {
      typeData: {
        rruleSet: {
          _rrule: [
            {
              origOptions: {
                freq: 3,
                dtstart: new Date(Date.UTC(2027, 2, 10, 10)),
                until: stampToDate(stamp),
              },
            },
          ],
        },
      },
    },
    title: "Open lab",
    extendedProps: { eventType: "other" },
  };
}

describe.each(Object.entries(ZONES))(
  "with the browser clock in %s",
  (zone, offsetOn17March) => {
    beforeEach(() => {
      process.env.TZ = zone;
      document.body.innerHTML = EVENT_MODAL_HTML;
    });

    it("has that zone", () => {
      expect(new Date(2027, 2, 17, 12).getTimezoneOffset()).toBe(
        offsetOn17March,
      );
    });

    describe("saving sends the instant of the Toronto time in the field", () => {
      for (const c of cases.fieldToInstant) {
        it(c.label, async () => {
          await openNew(c.field);
          submit();
          expect($("utc_start_time").value).toBe(c.instant);
          expect($("utc_end_time").value).toBe(c.instant);
        });
      }
    });

    describe("saving a repeating series writes its start in Toronto time", () => {
      for (const c of cases.fieldToInstant) {
        it(c.label, async () => {
          await openNew(c.field);
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
        it(c.label, async () => {
          await openNew("2027-03-10T10:00", "2027-03-10T11:00");
          $("recurrence_frequency").value = "DAILY";
          $("recurrence_until").value = c.date;
          submit();
          expect($("recurrence_rule_field").value).toContain(
            `UNTIL=${c.until}`,
          );
        });
      }
    });

    describe("opening an event from the calendar", () => {
      for (const c of cases.calendarStrings) {
        it(`shows ${c.label} at its Toronto time`, async () => {
          await load();
          eventClick(fcEvent(c.start));
          expect($("start_time_field").value).toBe(c.field);
        });

        it(`deletes ${c.label} by its own instant`, async () => {
          await load();
          eventClick(fcEvent(c.start));
          const sent = [...document.querySelectorAll(".delete_start_date")];
          expect(sent.map((input) => input.value)).toEqual([
            c.instant,
            c.instant,
          ]);
        });
      }

      for (const c of cases.untilDates) {
        it(`shows the repeat end date the feed sends for a series ending on ${c.label}`, async () => {
          await load();
          eventClick(
            fcEvent("2027-03-10T10:00:00", { _def: dailyUntil(c.served) }),
          );
          expect($("recurrence_until").value).toBe(c.date);
        });
      }
    });

    describe("selecting a range on the calendar", () => {
      for (const c of cases.calendarStrings.filter(
        (c) => !hasOffset(c.start),
      )) {
        it(`fills ${c.label} at its Toronto time`, async () => {
          await load();
          eventCreate({
            startStr: c.start,
            endStr: c.start,
            view: { calendar: { unselect() {} } },
          });
          expect($("start_time_field").value).toBe(c.field);
        });
      }
    });

    describe("the form", () => {
      it("makes an all-day entry on the day the clocks go forward Toronto midnight to midnight", async () => {
        await openNew("2027-03-14T10:30", "2027-03-14T11:30");
        $("all_day_checkbox").checked = true;
        fire($("all_day_checkbox"), "change");
        expect($("start_time_field").value).toBe("2027-03-14T00:00");
        expect($("end_time_field").value).toBe("2027-03-15T00:00");
      });

      it("saves that all-day entry as the 23 hours of the Toronto day", async () => {
        await openNew("2027-03-14T10:30", "2027-03-14T11:30");
        $("all_day_checkbox").checked = true;
        fire($("all_day_checkbox"), "change");
        submit();
        expect($("utc_start_time").value).toBe("2027-03-14T05:00:00.000Z");
        expect($("utc_end_time").value).toBe("2027-03-15T04:00:00.000Z");
      });

      it("ends an entry that is no longer all-day one hour after its start", async () => {
        await openNew("2027-03-14T01:30");
        $("all_day_checkbox").checked = false;
        fire($("all_day_checkbox"), "change");
        expect($("end_time_field").value).toBe("2027-03-14T03:30");
      });

      it("ticks the Toronto weekday of the start for a weekly event", async () => {
        await openNew("2027-03-17T22:30", "2027-03-17T23:00");
        $("recurrence_frequency").value = "WEEKLY";
        fire($("recurrence_frequency"), "change");
        const ticked = [...document.querySelectorAll(".dayCheckbox")]
          .filter((cb) => cb.checked)
          .map((cb) => cb.value);
        expect(ticked).toEqual(["WE"]);
      });

      it("proposes the next whole Toronto hour when the modal opens", async () => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date("2027-03-17T13:20:00Z"));
        try {
          await load();
          fire($("eventModal"), "show.bs.modal");
          expect($("start_time_field").value).toBe("2027-03-17T10:00");
          expect($("end_time_field").value).toBe("2027-03-17T11:00");
        } finally {
          vi.useRealTimers();
        }
      });
    });
  },
);
