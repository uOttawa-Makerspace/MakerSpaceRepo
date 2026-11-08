// These specs run with the clock in Toronto. The Vitest run itself leaves the
// zone alone (UTC), where a daylight-saving bug cannot show, so the zone is set
// here, before any date is built, and the first example checks that it took.
process.env.TZ = "America/Toronto";

import { describe, expect, it } from "vitest";
import {
  entryOverlaps,
  occurrencesOverlapping,
} from "../../../app/javascript/src/recurrence.js";

const at = (y, m, d, h = 0, mi = 0) => new Date(y, m - 1, d, h, mi);
const HOUR = 3600 * 1000;
const NINE_TO_TWENTY_PAST_TWO = 5 * HOUR + 20 * 60 * 1000;

// Wall-clock start and end ("9:00", "14:20") of every occurrence in a window.
function wallTimes(rule, duration, from, to) {
  return occurrencesOverlapping(rule, duration, from, to).map((o) => [
    `${o.start.getMonth() + 1}-${o.start.getDate()}`,
    `${o.start.getHours()}:${String(o.start.getMinutes()).padStart(2, "0")}`,
    `${o.end.getHours()}:${String(o.end.getMinutes()).padStart(2, "0")}`,
  ]);
}

// A Monday rule written in January and one written in July
const winterMondays = "DTSTART:20260105T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO";
const summerMondays = "DTSTART:20260706T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO";

describe("the test clock", () => {
  it("is Toronto, with the clocks going forward on 2026-03-08", () => {
    expect(at(2026, 3, 1, 12).getTimezoneOffset()).toBe(300);
    expect(at(2026, 3, 9, 12).getTimezoneOffset()).toBe(240);
  });
});

describe("occurrencesOverlapping", () => {
  it.each([
    ["the first Monday after spring-forward 2026", [2026, 3, 9], "3-9"],
    ["the Monday of the owner's report", [2026, 3, 30], "3-30"],
    ["a Monday in the middle of summer", [2026, 7, 20], "7-20"],
    ["the first Monday after fall-back", [2026, 11, 2], "11-2"],
    ["a Monday in the following winter", [2027, 1, 18], "1-18"],
  ])("keeps a rule written in winter at 9:00 on %s", (_, [y, m, d], day) => {
    const times = wallTimes(
      winterMondays,
      NINE_TO_TWENTY_PAST_TWO,
      at(y, m, d),
      at(y, m, d + 1),
    );
    expect(times).toEqual([[day, "9:00", "14:20"]]);
  });

  it.each([
    ["before spring-forward", [2027, 3, 8], "3-8"],
    ["in the winter after", [2026, 12, 7], "12-7"],
  ])("keeps a rule written in summer at 9:00 %s", (_, [y, m, d], day) => {
    const times = wallTimes(
      summerMondays,
      NINE_TO_TWENTY_PAST_TWO,
      at(y, m, d),
      at(y, m, d + 1),
    );
    expect(times).toEqual([[day, "9:00", "14:20"]]);
  });

  it.each([
    ["2026-03-08, the day the clocks go forward", [2026, 3, 8], "3-8"],
    ["2026-11-01, the day the clocks go back", [2026, 11, 1], "11-1"],
    ["2027-03-14, the next spring-forward", [2027, 3, 14], "3-14"],
  ])("keeps a Sunday rule at 9:00 on %s", (_, [y, m, d], day) => {
    const times = wallTimes(
      "DTSTART:20260104T090000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      HOUR,
      at(y, m, d),
      at(y, m, d + 1),
    );
    expect(times).toEqual([[day, "9:00", "10:00"]]);
  });

  it("finds an occurrence that started before the window and runs into it", () => {
    const times = wallTimes(
      winterMondays,
      NINE_TO_TWENTY_PAST_TWO,
      at(2026, 3, 30, 14),
      at(2026, 3, 30, 15),
    );
    expect(times).toEqual([["3-30", "9:00", "14:20"]]);
  });

  it("leaves out an occurrence that only touches the window", () => {
    const times = wallTimes(
      winterMondays,
      NINE_TO_TWENTY_PAST_TWO,
      at(2026, 3, 30, 14, 20),
      at(2026, 3, 30, 15),
    );
    expect(times).toEqual([]);
  });

  it("stops after the UNTIL, an instant written in UTC", () => {
    // 2026-03-24T03:59:59Z is the end of Monday 2026-03-23 in Toronto
    const rule = `${winterMondays};UNTIL=20260324T035959Z`;
    const days = wallTimes(rule, HOUR, at(2026, 3, 9), at(2026, 4, 14)).map(
      ([day]) => day,
    );
    expect(days).toEqual(["3-9", "3-16", "3-23"]);
  });

  it("stops after an UNTIL in winter", () => {
    // 2026-01-13T04:59:59Z is the end of Monday 2026-01-12 in Toronto
    const rule = `${winterMondays};UNTIL=20260113T045959Z`;
    const days = wallTimes(rule, HOUR, at(2026, 1, 1), at(2026, 3, 1)).map(
      ([day]) => day,
    );
    expect(days).toEqual(["1-5", "1-12"]);
  });

  it("skips an EXDATE written in wall-clock time", () => {
    const rule = `${winterMondays}\nEXDATE:20260316T090000`;
    const days = wallTimes(rule, HOUR, at(2026, 3, 9), at(2026, 3, 24)).map(
      ([day]) => day,
    );
    expect(days).toEqual(["3-9", "3-23"]);
  });

  it("skips an EXDATE written as a UTC instant", () => {
    // 13:00Z is 9:00 in Toronto after spring-forward
    const rule = `${winterMondays}\nEXDATE:20260316T130000Z`;
    const days = wallTimes(rule, HOUR, at(2026, 3, 9), at(2026, 3, 24)).map(
      ([day]) => day,
    );
    expect(days).toEqual(["3-9", "3-23"]);
  });

  it("reads a rule that starts at an instant (a rule built in the browser)", () => {
    // Monday 2026-03-30 10:00 in Toronto is 14:00Z
    const rule = "DTSTART:20260330T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO";
    const times = wallTimes(rule, HOUR, at(2026, 3, 30), at(2026, 4, 14));
    expect(times).toEqual([
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
        at(2026, 3, 1),
        at(2026, 3, 2),
      ),
    ).toThrow();
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
      entryOverlaps(monday, at(2026, 3, 30, 9, 30), at(2026, 3, 30, 10)),
    ).toBe(true);
    expect(
      entryOverlaps(monday, at(2026, 3, 30, 14, 30), at(2026, 3, 30, 15, 30)),
    ).toBe(false);
  });

  it("matches a one-off entry by its overlap", () => {
    const oneOff = { start: "2026-03-30T09:00:00", end: "2026-03-30T10:00:00" };
    expect(
      entryOverlaps(oneOff, at(2026, 3, 30, 9, 59), at(2026, 3, 30, 11)),
    ).toBe(true);
    expect(
      entryOverlaps(oneOff, at(2026, 3, 30, 10), at(2026, 3, 30, 11)),
    ).toBe(false);
  });

  it("warns and matches nothing for a rule it cannot read", () => {
    const broken = { ...monday, rrule: "RRULE:FREQ=NEVER" };
    expect(entryOverlaps(broken, at(2026, 3, 30, 9), at(2026, 3, 30, 10))).toBe(
      false,
    );
  });
});
