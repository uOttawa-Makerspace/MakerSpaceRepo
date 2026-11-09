// A repeating entry is read and expanded once for a whole range, not once per
// event occurrence, and an entry that cannot reach the range is skipped.
import { beforeEach, describe, expect, it, vi } from "vitest";

const parse = vi.hoisted(() => ({ calls: 0, between: 0 }));
vi.mock("rrule", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    rrulestr: (...args) => {
      parse.calls += 1;
      const rule = actual.rrulestr(...args);
      const between = rule.between.bind(rule);
      rule.between = (...range) => {
        parse.between += 1;
        return between(...range);
      };
      return rule;
    },
  };
});

import { entryIntervals } from "../../../app/javascript/src/recurrence.js";

const wall = (y, m, d, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h, mi);
const HOUR = 3600 * 1000;
const MONDAYS = {
  rrule: "DTSTART:20200106T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO",
  duration: 5 * HOUR,
};

describe("entryIntervals", () => {
  beforeEach(() => {
    parse.calls = 0;
    parse.between = 0;
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
      expect(covered(start)).toBe(
        entryIntervals(MONDAYS, start, start + HOUR).length > 0,
      );
    }
  });

  it("does not expand a rule that ended before the range", () => {
    const rule = "DTSTART:20200106T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO";
    const range = [wall(2026, 3, 2), wall(2026, 3, 30)];
    const ended = { ...MONDAYS, rrule: `${rule};UNTIL=20200301T000000` };
    expect(entryIntervals(ended, ...range)).toEqual([]);
    expect(parse.between).toBe(0);
    expect(entryIntervals(MONDAYS, ...range)).not.toEqual([]);
    expect(parse.between).toBe(1);
  });

  it("skips a one-off outside the range without parsing", () => {
    const oneOff = { start: "2025-01-01T09:00", end: "2025-01-01T10:00" };
    expect(entryIntervals(oneOff, wall(2026, 3, 2), wall(2026, 3, 30))).toEqual(
      [],
    );
    expect(parse.calls).toBe(0);
  });
});
