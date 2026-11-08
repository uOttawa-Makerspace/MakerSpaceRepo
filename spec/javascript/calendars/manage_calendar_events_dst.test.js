// @vitest-environment happy-dom
// The staff ranking in the event modal. The form fields and the feed are
// Toronto wall-clock times, so the ranking must be the same whatever the zone
// of the browser: every example runs with the process clock in Toronto, in
// Paris and in UTC (the Vitest run itself leaves it in UTC alone).
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
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
    constructor() {
      this.handlers = {};
      tomInstances.push(this);
    }
    on(name, fn) {
      this.handlers[name] = fn;
    }
    sync() {}
    clearOptions() {}
    addOption() {}
    destroy() {}
    setTextboxValue() {}
  },
}));

await import("../../../app/javascript/src/manage_calendar_events.js");

const $ = (id) => document.getElementById(id);

// Ada works Mondays 9:00-14:20 from a rule written in January; Bob is free.
const feed = [
  {
    id: 1,
    name: "Ada",
    color: "#f00",
    unavailabilities: [
      {
        start: "2026-01-05T09:00:00",
        end: "2026-01-05T14:20:00",
        duration: (5 * 60 + 20) * 60 * 1000,
        rrule: "DTSTART:20260105T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO",
      },
    ],
  },
  { id: 2, name: "Bob", color: "#0f0", unavailabilities: [] },
];

async function load() {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => feed })),
  );
  document.dispatchEvent(new Event("turbo:load"));
  await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function setTimes(start, end) {
  $("start_time_field").value = start;
  $("end_time_field").value = end;
  $("end_time_field").dispatchEvent(new Event("change"));
}

const availableFirst = () =>
  [...$("staff_select").options].map((o) => o.textContent);
const adaIsFlagged = () =>
  availableFirst()[0] === "Bob" && availableFirst()[1] === "Ada";

const ZONES = {
  "America/Toronto": 240,
  "Europe/Paris": -120,
  UTC: 0,
};
const originalZone = process.env.TZ;
afterAll(() => {
  if (originalZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalZone;
});

describe.each(Object.entries(ZONES))(
  "with the browser clock in %s",
  (zone, offsetOn30March) => {
    beforeEach(async () => {
      process.env.TZ = zone;
      tomInstances.length = 0;
      document.body.innerHTML = EVENT_MODAL_HTML;
      await load();
    });

    it("has that zone", () => {
      expect(new Date(2026, 2, 30, 12).getTimezoneOffset()).toBe(
        offsetOn30March,
      );
    });

    describe("a Monday 9:00-14:20 rule written in winter", () => {
      it.each([
        [
          "flags 9:30 on 2026-03-30, the day of the report",
          "2026-03-30T09:30",
          "2026-03-30T10:00",
          true,
        ],
        [
          "flags 14:00 on 2026-03-30",
          "2026-03-30T14:00",
          "2026-03-30T14:30",
          true,
        ],
        [
          "does not flag 14:20 on 2026-03-30 (the shift is over)",
          "2026-03-30T14:20",
          "2026-03-30T15:00",
          false,
        ],
        [
          "does not flag 8:00-9:00 on 2026-03-30",
          "2026-03-30T08:00",
          "2026-03-30T09:00",
          false,
        ],
        [
          "flags 9:30 on 2026-03-09, the first Monday after spring-forward",
          "2026-03-09T09:30",
          "2026-03-09T10:00",
          true,
        ],
        [
          "flags 9:30 on 2026-11-02, after the clocks go back",
          "2026-11-02T09:30",
          "2026-11-02T10:00",
          true,
        ],
        [
          "does not flag 15:00 on 2026-11-02",
          "2026-11-02T15:00",
          "2026-11-02T16:00",
          false,
        ],
        [
          "flags 9:30 on 2027-03-15, after the next spring-forward",
          "2027-03-15T09:30",
          "2027-03-15T10:00",
          true,
        ],
      ])("%s", (_, start, end, flagged) => {
        setTimes(start, end);
        expect(adaIsFlagged()).toBe(flagged);
      });

      it("does not flag a Sunday, the day of the clock change", () => {
        setTimes("2026-03-08T09:30", "2026-03-08T10:00");
        expect(adaIsFlagged()).toBe(false);
      });
    });

    describe("a repeating event", () => {
      it("is flagged on every Monday occurrence, across the clock change", () => {
        // Mondays 14:00-14:30 from 2026-03-02 (before the change) for four weeks
        setTimes("2026-03-02T14:00", "2026-03-02T14:30");
        $("recurrence_frequency").value = "WEEKLY";
        $("day_MO").checked = true;
        // the rule is built when the picker takes focus
        tomInstances[0].handlers.focus();
        const ada = [...$("staff_select").options].find(
          (o) => o.textContent === "Ada",
        );
        const starts = ada.dataset.unavailableDates
          .split(",")
          .map((text) => new Date(text).toISOString());
        // 14:00 in Toronto: 19:00Z before the change, 18:00Z after it
        expect(starts).toEqual([
          "2026-03-02T19:00:00.000Z",
          "2026-03-09T18:00:00.000Z",
          "2026-03-16T18:00:00.000Z",
          "2026-03-23T18:00:00.000Z",
        ]);
      });
    });
  },
);
