// Recurrence works on Toronto wall-clock times and must not depend on the zone
// of the browser. Every example runs three times with the process clock set to
// a different zone (the Vitest run itself leaves it in UTC, where a
// daylight-saving bug in the host zone could not show).
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  entryOverlaps,
  instantToWall,
  occurrencesOverlapping,
  startingAt,
  wallFromString,
  wallToInstant,
} from "../../../app/javascript/src/recurrence.js";

const ZONES = ["America/Toronto", "Europe/Paris", "UTC"];
const originalZone = process.env.TZ;
afterAll(() => {
  if (originalZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalZone;
});

// A wall time from its fields, and its parts back as text
const wall = (y, m, d, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h, mi);
const clock = (ms) => {
  const d = new Date(ms);
  return `${d.getUTCHours()}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
};
const day = (ms) =>
  `${new Date(ms).getUTCMonth() + 1}-${new Date(ms).getUTCDate()}`;
const HOUR = 3600 * 1000;
const NINE_TO_TWENTY_PAST_TWO = 5 * HOUR + 20 * 60 * 1000;

function occurrences(rule, duration, from, to) {
  return occurrencesOverlapping(rule, duration, from, to).map((o) => [
    day(o.start),
    clock(o.start),
    clock(o.end),
  ]);
}
const days = (rule, duration, from, to) =>
  occurrences(rule, duration, from, to).map(([d]) => d);

// A Monday rule written in January and one written in July
const winterMondays = "DTSTART:20260105T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO";
const summerMondays = "DTSTART:20260706T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO";

describe.each(ZONES)("with the process clock in %s", (zone) => {
  beforeEach(() => {
    process.env.TZ = zone;
  });

  describe("the wall time of an instant", () => {
    it("is read in Toronto", () => {
      // 13:00Z is 9:00 in EDT (March 30) and 8:00 in EST (January 5 is 14:00Z)
      expect(instantToWall(Date.parse("2026-03-30T13:00:00Z"))).toBe(
        wall(2026, 3, 30, 9),
      );
      expect(instantToWall(Date.parse("2026-01-05T14:00:00Z"))).toBe(
        wall(2026, 1, 5, 9),
      );
    });

    it.each([
      ["a winter time", wall(2026, 1, 5, 9), "2026-01-05T14:00:00.000Z"],
      ["a summer time", wall(2026, 3, 30, 9), "2026-03-30T13:00:00.000Z"],
      [
        "a time skipped by the clocks going forward (as 3:30)",
        wall(2026, 3, 8, 2, 30),
        "2026-03-08T07:30:00.000Z",
      ],
      [
        "a time that happens twice when the clocks go back (the first)",
        wall(2026, 11, 1, 1, 30),
        "2026-11-01T05:30:00.000Z",
      ],
      [
        "the second 2:30 of the day the clocks go back",
        wall(2026, 11, 1, 2, 30),
        "2026-11-01T07:30:00.000Z",
      ],
    ])("gives the instant of %s", (_, wallMs, iso) => {
      expect(new Date(wallToInstant(wallMs)).toISOString()).toBe(iso);
    });

    it("reads a form value as a wall time", () => {
      expect(wallFromString("2026-03-30T09:30")).toBe(wall(2026, 3, 30, 9, 30));
      expect(wallFromString("2026-03-30T09:30:15")).toBe(
        wall(2026, 3, 30, 9, 30) + 15000,
      );
    });
  });

  describe("occurrencesOverlapping", () => {
    it.each([
      ["the first Monday after spring-forward 2026", [2026, 3, 9], "3-9"],
      ["the Monday of the owner's report", [2026, 3, 30], "3-30"],
      ["a Monday in the middle of summer", [2026, 7, 20], "7-20"],
      ["the first Monday after fall-back", [2026, 11, 2], "11-2"],
      ["a Monday in the following winter", [2027, 1, 18], "1-18"],
    ])(
      "keeps a rule written in winter at 9:00 on %s",
      (_, [y, m, d], label) => {
        const found = occurrences(
          winterMondays,
          NINE_TO_TWENTY_PAST_TWO,
          wall(y, m, d),
          wall(y, m, d + 1),
        );
        expect(found).toEqual([[label, "9:00", "14:20"]]);
      },
    );

    it.each([
      ["before spring-forward", [2027, 3, 8], "3-8"],
      ["in the winter after", [2026, 12, 7], "12-7"],
    ])("keeps a rule written in summer at 9:00 %s", (_, [y, m, d], label) => {
      const found = occurrences(
        summerMondays,
        NINE_TO_TWENTY_PAST_TWO,
        wall(y, m, d),
        wall(y, m, d + 1),
      );
      expect(found).toEqual([[label, "9:00", "14:20"]]);
    });

    it.each([
      ["2026-03-08, the day the clocks go forward", [2026, 3, 8], "3-8"],
      ["2026-11-01, the day the clocks go back", [2026, 11, 1], "11-1"],
      ["2027-03-14, the next spring-forward", [2027, 3, 14], "3-14"],
    ])("keeps a Sunday rule at 9:00 on %s", (_, [y, m, d], label) => {
      const found = occurrences(
        "DTSTART:20260104T090000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
        HOUR,
        wall(y, m, d),
        wall(y, m, d + 1),
      );
      expect(found).toEqual([[label, "9:00", "10:00"]]);
    });

    it("keeps a 2:30 rule on the night the clocks go forward", () => {
      const rule = "DTSTART:20260301T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU";
      const found = occurrencesOverlapping(
        rule,
        HOUR,
        wall(2026, 3, 8),
        wall(2026, 3, 9),
      );
      expect(found.map((o) => [day(o.start), clock(o.start)])).toEqual([
        ["3-8", "2:30"],
      ]);
      // its instant is 3:30 EDT
      expect(new Date(wallToInstant(found[0].start)).toISOString()).toBe(
        "2026-03-08T07:30:00.000Z",
      );
    });

    it("keeps a 1:30 rule on the night the clocks go back", () => {
      const rule = "DTSTART:20261025T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU";
      const found = occurrencesOverlapping(
        rule,
        HOUR,
        wall(2026, 11, 1),
        wall(2026, 11, 2),
      );
      expect(found.map((o) => [day(o.start), clock(o.start)])).toEqual([
        ["11-1", "1:30"],
      ]);
      expect(new Date(wallToInstant(found[0].start)).toISOString()).toBe(
        "2026-11-01T05:30:00.000Z",
      );
    });

    it.each([
      ["clocks go back", [2026, 11, 1], "10-31"],
      ["clocks go forward", [2026, 3, 8], "3-7"],
    ])(
      "ends a Saturday 22:00 rule of six hours at 4:00 when the %s",
      (_, [y, m, d], saturday) => {
        const rule = "DTSTART:20260103T220000\nRRULE:FREQ=WEEKLY;BYDAY=SA";
        const found = occurrences(
          rule,
          6 * HOUR,
          wall(y, m, d - 1),
          wall(y, m, d + 1),
        );
        expect(found).toEqual([[saturday, "22:00", "4:00"]]);
        // the shift is still on at 3:59 and over at 4:00
        expect(
          occurrencesOverlapping(
            rule,
            6 * HOUR,
            wall(y, m, d, 3, 59),
            wall(y, m, d, 5),
          ),
        ).toHaveLength(1);
        expect(
          occurrencesOverlapping(
            rule,
            6 * HOUR,
            wall(y, m, d, 4),
            wall(y, m, d, 5),
          ),
        ).toHaveLength(0);
      },
    );

    it("finds an occurrence that started before the range and runs into it", () => {
      const found = occurrences(
        winterMondays,
        NINE_TO_TWENTY_PAST_TWO,
        wall(2026, 3, 30, 14),
        wall(2026, 3, 30, 15),
      );
      expect(found).toEqual([["3-30", "9:00", "14:20"]]);
    });

    it("leaves out an occurrence that only touches the range", () => {
      const found = occurrences(
        winterMondays,
        NINE_TO_TWENTY_PAST_TWO,
        wall(2026, 3, 30, 14, 20),
        wall(2026, 3, 30, 15),
      );
      expect(found).toEqual([]);
    });

    it("stops after the UNTIL, an instant written in UTC", () => {
      // 2026-03-24T03:59:59Z is the end of Monday 2026-03-23 in Toronto
      const rule = `${winterMondays};UNTIL=20260324T035959Z`;
      expect(days(rule, HOUR, wall(2026, 3, 9), wall(2026, 4, 14))).toEqual([
        "3-9",
        "3-16",
        "3-23",
      ]);
    });

    it("stops after an UNTIL in winter", () => {
      // 2026-01-13T04:59:59Z is the end of Monday 2026-01-12 in Toronto
      const rule = `${winterMondays};UNTIL=20260113T045959Z`;
      expect(days(rule, HOUR, wall(2026, 1, 1), wall(2026, 3, 1))).toEqual([
        "1-5",
        "1-12",
      ]);
    });

    it("skips an EXDATE written in wall-clock time", () => {
      const rule = `${winterMondays}\nEXDATE:20260316T090000`;
      expect(days(rule, HOUR, wall(2026, 3, 9), wall(2026, 3, 24))).toEqual([
        "3-9",
        "3-23",
      ]);
    });

    it("skips an EXDATE written as a UTC instant", () => {
      // 13:00Z is 9:00 in Toronto after spring-forward
      const rule = `${winterMondays}\nEXDATE:20260316T130000Z`;
      expect(days(rule, HOUR, wall(2026, 3, 9), wall(2026, 3, 24))).toEqual([
        "3-9",
        "3-23",
      ]);
    });

    it("reads a rule that starts at an instant", () => {
      // Monday 2026-03-30 10:00 in Toronto is 14:00Z
      const rule = "DTSTART:20260330T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO";
      expect(
        occurrences(rule, HOUR, wall(2026, 3, 30), wall(2026, 4, 14)),
      ).toEqual([
        ["3-30", "10:00", "11:00"],
        ["4-6", "10:00", "11:00"],
        ["4-13", "10:00", "11:00"],
      ]);
    });

    it("refuses a rule it cannot read", () => {
      expect(() =>
        occurrencesOverlapping(
          "RRULE:FREQ=NEVER",
          HOUR,
          wall(2026, 3, 1),
          wall(2026, 3, 2),
        ),
      ).toThrow();
    });
  });

  describe("startingAt", () => {
    it("replaces the start of a rule built in the browser with a wall time", () => {
      const built = "DTSTART:20260330T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO";
      const rule = startingAt(built, wall(2026, 3, 30, 14));
      expect(
        occurrences(rule, HOUR, wall(2026, 3, 30), wall(2026, 4, 7)),
      ).toEqual([
        ["3-30", "14:00", "15:00"],
        ["4-6", "14:00", "15:00"],
      ]);
    });
  });

  describe("entryOverlaps", () => {
    const monday = {
      start: "2026-01-05T09:00:00",
      end: "2026-01-05T14:20:00",
      duration: NINE_TO_TWENTY_PAST_TWO,
      rrule: winterMondays,
    };

    it("matches a repeating entry on a day after spring-forward", () => {
      expect(
        entryOverlaps(monday, wall(2026, 3, 30, 9, 30), wall(2026, 3, 30, 10)),
      ).toBe(true);
      expect(
        entryOverlaps(
          monday,
          wall(2026, 3, 30, 14, 30),
          wall(2026, 3, 30, 15, 30),
        ),
      ).toBe(false);
    });

    it("matches a one-off entry by its overlap", () => {
      const oneOff = {
        start: "2026-03-30T09:00:00",
        end: "2026-03-30T10:00:00",
      };
      expect(
        entryOverlaps(oneOff, wall(2026, 3, 30, 9, 59), wall(2026, 3, 30, 11)),
      ).toBe(true);
      expect(
        entryOverlaps(oneOff, wall(2026, 3, 30, 10), wall(2026, 3, 30, 11)),
      ).toBe(false);
    });

    it("matches nothing for a rule it cannot read", () => {
      const broken = { ...monday, rrule: "RRULE:FREQ=NEVER" };
      expect(
        entryOverlaps(broken, wall(2026, 3, 30, 9), wall(2026, 3, 30, 10)),
      ).toBe(false);
    });
  });
});
