// A repeating entry is read and expanded once for a whole range, not once per
// event occurrence, and an entry that cannot reach the range is skipped.
import { beforeEach, describe, expect, it, vi } from "vitest";

const parse = vi.hoisted(() => ({ calls: 0 }));
vi.mock("rrule", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    rrulestr: (...args) => {
      parse.calls += 1;
      return actual.rrulestr(...args);
    },
  };
});

import {
  entryIntervals,
  entryOverlaps,
} from "../../../app/javascript/src/recurrence.js";

const wall = (y, m, d, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h, mi);
const HOUR = 3600 * 1000;
const MONDAYS = {
  rrule: "DTSTART:20200106T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO",
  duration: 5 * HOUR,
};

describe("entryIntervals", () => {
  beforeEach(() => {
    parse.calls = 0;
  });

  it("parses a repeating entry once for a four week range", () => {
    const from = wall(2026, 3, 2, 8);
    const to = wall(2026, 3, 30, 10);
    const intervals = entryIntervals(MONDAYS, from, to);
    expect(intervals).toHaveLength(5);
    expect(parse.calls).toBe(1);
  });

  it("gives the same answer as asking about each day separately", () => {
    const from = wall(2026, 3, 2, 8);
    const to = wall(2026, 3, 30, 10);
    const covered = (start) =>
      entryIntervals(MONDAYS, from, to).some(
        (slot) => slot.start < start + HOUR && slot.end > start,
      );
    for (let day = 0; day < 28; day += 1) {
      const start = from + day * 24 * HOUR;
      expect(covered(start)).toBe(entryOverlaps(MONDAYS, start, start + HOUR));
    }
  });

  it("skips a rule that ended before the range", () => {
    const ended = {
      ...MONDAYS,
      rrule:
        "DTSTART:20200106T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20200301T000000",
    };
    expect(entryIntervals(ended, wall(2026, 3, 2), wall(2026, 3, 30))).toEqual(
      [],
    );
  });

  it("skips a one-off outside the range without parsing", () => {
    const oneOff = { start: "2025-01-01T09:00", end: "2025-01-01T10:00" };
    expect(entryIntervals(oneOff, wall(2026, 3, 2), wall(2026, 3, 30))).toEqual(
      [],
    );
    expect(parse.calls).toBe(0);
  });
});
