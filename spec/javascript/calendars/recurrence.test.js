// Recurrence works on Toronto wall-clock times and must not depend on the zone
// of the browser. Every example runs three times with the process clock set to
// a different zone (the Vitest run itself leaves it in UTC, where a
// daylight-saving bug in the host zone could not show).
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  dateValue,
  endOfDateInstant,
  fieldValue,
  instantFromCalendar,
  instantToWall,
  startOfDay,
  wallFromCalendar,
  wallOfField,
  wallFromString,
  wallToInstant,
} from "../../../app/javascript/src/recurrence.js";

const ZONES = ["America/Toronto", "Europe/Paris", "UTC"];
// Offset of each zone on 2026-03-30, in minutes as getTimezoneOffset reports it
const OFFSET_ON_30_MARCH = {
  "America/Toronto": 240,
  "Europe/Paris": -120,
  UTC: 0,
};
const originalZone = process.env.TZ;
afterAll(() => {
  if (originalZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalZone;
});

// A wall time from its fields
const wall = (y, m, d, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h, mi);

describe.each(ZONES)("with the process clock in %s", (zone) => {
  beforeEach(() => {
    process.env.TZ = zone;
  });

  it("has that zone", () => {
    expect(new Date(2026, 2, 30, 12).getTimezoneOffset()).toBe(
      OFFSET_ON_30_MARCH[zone],
    );
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

  describe("form and calendar values", () => {
    it("writes a wall time as a datetime field and as a date field", () => {
      expect(fieldValue(wall(2026, 3, 30, 9, 5))).toBe("2026-03-30T09:05");
      expect(dateValue(wall(2026, 3, 30, 23, 59))).toBe("2026-03-30");
    });

    it("reads an empty field as now in Toronto", () => {
      const before = instantToWall(Date.now());
      const now = wallOfField("");
      expect(now).toBeGreaterThanOrEqual(before);
      expect(now).toBeLessThanOrEqual(instantToWall(Date.now()));
      expect(wallOfField("2026-03-30T09:30")).toBe(wall(2026, 3, 30, 9, 30));
    });

    it("finds the midnight starting a day", () => {
      expect(startOfDay(wall(2026, 3, 8, 23, 30))).toBe(wall(2026, 3, 8));
    });

    it.each([
      ["a time with an offset as an instant", "2026-03-30T09:30:00-04:00"],
      ["a time in UTC as an instant", "2026-03-30T13:30:00Z"],
      ["a time without a zone as Toronto time", "2026-03-30T09:30:00"],
    ])("reads %s", (_, value) => {
      expect(wallFromCalendar(value)).toBe(wall(2026, 3, 30, 9, 30));
    });

    it("keeps the instant of a calendar time with an offset", () => {
      // the second 1:30 of the night the clocks go back
      expect(
        new Date(
          instantFromCalendar("2026-11-01T01:30:00-05:00"),
        ).toISOString(),
      ).toBe("2026-11-01T06:30:00.000Z");
      expect(
        new Date(instantFromCalendar("2026-11-01T01:30:00")).toISOString(),
      ).toBe("2026-11-01T05:30:00.000Z");
    });

    it("reads a calendar date alone as its midnight", () => {
      expect(wallFromCalendar("2026-03-30")).toBe(wall(2026, 3, 30));
    });

    it("ends a repeat on the last second of the Toronto day", () => {
      expect(new Date(endOfDateInstant("2026-03-08")).toISOString()).toBe(
        "2026-03-09T03:59:59.000Z",
      );
      expect(new Date(endOfDateInstant("2026-01-09")).toISOString()).toBe(
        "2026-01-10T04:59:59.000Z",
      );
    });
  });
});
