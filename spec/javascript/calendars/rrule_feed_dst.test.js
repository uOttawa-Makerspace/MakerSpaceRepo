// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { Calendar } from "@fullcalendar/core";
import timeGridPlugin from "@fullcalendar/timegrid";
import rrulePlugin from "@fullcalendar/rrule";
import { rrulestr } from "rrule";
import {
  wallToInstant,
  wallFromString,
} from "../../../app/javascript/src/recurrence";
import feedRows from "../../fixtures/files/ics/feed_events.json";

// What the browser draws for a repeating series across the two America/Toronto
// clock changes of 2027 (forward Sunday 2027-03-14 at 02:00, back Sunday
// 2027-11-07 at 02:00). The rule strings are the ones the three calendar feeds
// (admin events, admin unavailabilities, staff unavailabilities) send; they
// are pinned on the server side in
// spec/requests/calendar_rrule_feed_dst_request_spec.rb, which also lists the
// occurrences the server's own expansion gives for the same series. The pages
// run each string through rrulestr(...).toString() and give it to
// @fullcalendar/rrule with timeZone America/Toronto.
function drawn(rule, weeks) {
  const starts = new Set();
  weeks.forEach((initialDate) => {
    const el = document.createElement("div");
    document.body.appendChild(el);
    const calendar = new Calendar(el, {
      plugins: [timeGridPlugin, rrulePlugin],
      timeZone: "America/Toronto",
      initialView: "timeGridWeek",
      initialDate,
      events: [
        { id: "series", rrule: rrulestr(rule).toString(), duration: 3600000 },
      ],
    });
    calendar.render();
    calendar.getEvents().forEach((event) => starts.add(event.startStr));
    calendar.destroy();
  });
  return [...starts].sort();
}

const FALL_WEEKS = ["2027-10-31", "2027-11-07", "2027-11-14", "2027-11-21"];
const SPRING_WEEKS = ["2027-03-07", "2027-03-14", "2027-03-21"];

describe("a weekly series across the clocks going back", () => {
  const series = "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU";

  it("draws each Sunday at 01:30, the repeated hour once", () => {
    expect(drawn(series, FALL_WEEKS)).toEqual([
      "2027-10-31T01:30:00",
      "2027-11-07T01:30:00",
      "2027-11-14T01:30:00",
      "2027-11-21T01:30:00",
      "2027-11-28T01:30:00",
    ]);
  });

  it("leaves out the day whose 01:30 is excluded", () => {
    // the feed sends the same line for an exclusion stamped at the first 01:30
    // (05:30 UTC) and at the second (06:30 UTC)
    expect(drawn(`${series}\nEXDATE:20271107T013000`, FALL_WEEKS)).toEqual([
      "2027-10-31T01:30:00",
      "2027-11-14T01:30:00",
      "2027-11-21T01:30:00",
      "2027-11-28T01:30:00",
    ]);
  });

  it("draws a series at 10:00 at 10:00 on both sides of the change", () => {
    const morning = "DTSTART:20271031T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU";
    expect(drawn(morning, FALL_WEEKS)).toEqual([
      "2027-10-31T10:00:00",
      "2027-11-07T10:00:00",
      "2027-11-14T10:00:00",
      "2027-11-21T10:00:00",
      "2027-11-28T10:00:00",
    ]);
  });
});

describe("a weekly series across the clocks going forward", () => {
  it("draws a series at 10:00 at 10:00 on both sides of the change", () => {
    const morning = "DTSTART:20270307T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU";
    expect(drawn(morning, SPRING_WEEKS)).toEqual([
      "2027-03-07T10:00:00",
      "2027-03-14T10:00:00",
      "2027-03-21T10:00:00",
      "2027-03-28T10:00:00",
    ]);
  });

  // The server's expansion moves the skipped 02:30 forward to 03:30 on the
  // change day; the browser has no time zones in its repeat rule, so it draws
  // the series at 02:30 that day.
  it("draws a series at 02:30 at 02:30 on the change day too", () => {
    const skipped = "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU";
    expect(drawn(skipped, SPRING_WEEKS)).toEqual([
      "2027-03-07T02:30:00",
      "2027-03-14T02:30:00",
      "2027-03-21T02:30:00",
      "2027-03-28T02:30:00",
    ]);
  });

  it("does not hide the change-day occurrence when it is excluded at the instant the modal sends", () => {
    // the modal turns the clicked 02:30 into an instant, 03:30 daylight time
    const instant = new Date(wallToInstant(wallFromString("2027-03-14T02:30")));
    expect(instant.toISOString()).toBe("2027-03-14T07:30:00.000Z");
    // the feed writes that exclusion as the Toronto wall time 03:30
    const rule =
      "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T033000";
    expect(drawn(rule, SPRING_WEEKS)).toEqual([
      "2027-03-07T02:30:00",
      "2027-03-14T02:30:00",
      "2027-03-21T02:30:00",
      "2027-03-28T02:30:00",
    ]);
  });
});

// ---- Imported calendars (ICS) ----
//
// The rows are the events spec/helpers/calendar_helper_ics_dst_spec.rb builds from the files in
// spec/fixtures/files/ics (saved in feed_events.json; that spec fails if the file and the helper
// disagree). The admin imported calendars feed and the open hours feed give the rows straight to
// @fullcalendar/rrule, as here. Each example draws one calendar over several weeks and names the
// disagreements with what the file means; the slices that expand imported calendars on the server
// change those expectations and nothing else.
function rowsOf(fixture) {
  return feedRows[fixture];
}

function rowOf(fixture, id) {
  return rowsOf(fixture).find((row) => row.id === id);
}

// What the calendar draws for a feed row: "start..end" for each event, over `days` days from `from`.
function drawnRow(row, from, days) {
  const el = document.createElement("div");
  document.body.appendChild(el);
  const calendar = new Calendar(el, {
    plugins: [timeGridPlugin, rrulePlugin],
    timeZone: "America/Toronto",
    initialView: "span",
    views: { span: { type: "timeGrid", duration: { days } } },
    initialDate: from,
    events: [
      row.rrule
        ? {
            id: row.id,
            allDay: row.allDay,
            rrule: row.rrule,
            duration: row.duration,
          }
        : { id: row.id, allDay: row.allDay, start: row.start, end: row.end },
    ],
  });
  calendar.render();
  const events = calendar
    .getEvents()
    .map((event) => `${event.startStr}..${event.endStr}`);
  calendar.destroy();
  return events.sort();
}

// "2027-03-07T02:30:00..2027-03-07T03:30:00" for each date, from clock time to clock time.
function at(dates, from, to) {
  return dates.map((date) => `${date}T${from}..${date}T${to}`);
}

// Whole days, as an all-day event is drawn.
function onDays(dates) {
  return dates.map((date) => {
    const next = new Date(`${date}T00:00:00Z`);
    next.setUTCDate(next.getUTCDate() + 1);
    return `${date}..${next.toISOString().slice(0, 10)}`;
  });
}

const SPRING_SUNDAYS = [
  "2027-03-07",
  "2027-03-14",
  "2027-03-21",
  "2027-03-28",
  "2027-04-04",
];
const FALL_SUNDAYS = [
  "2027-10-31",
  "2027-11-07",
  "2027-11-14",
  "2027-11-21",
  "2027-11-28",
];
const SPRING_FROM = "2027-02-28";
const FALL_FROM = "2027-10-24";
const FIVE_WEEKS = 35;

describe("an imported calendar in the Toronto zone", () => {
  // Disagreement "skipped hour": the series is drawn at 02:30 on 2027-03-14, an hour that does not exist (the
  // server's expansion of the same text gives 03:30; see calendar_helper_ics_dst_spec.rb).
  it("draws a series at 02:30 at 02:30 on the day the clocks go forward", () => {
    const row = rowOf("toronto_tzid", "spring-0230@ics.test");
    expect(drawnRow(row, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(SPRING_SUNDAYS, "02:30:00", "03:30:00"),
    );
  });

  it("draws a series at 01:30 once on the day the clocks go back", () => {
    const row = rowOf("toronto_tzid", "fall-0130@ics.test");
    expect(drawnRow(row, FALL_FROM, FIVE_WEEKS)).toEqual(
      at(FALL_SUNDAYS, "01:30:00", "02:30:00"),
    );
  });

  it("draws a calendar with a Windows zone name and its own VTIMEZONE like a Toronto one", () => {
    expect(
      drawnRow(
        rowOf("windows_timezone", "windows-spring@ics.test"),
        SPRING_FROM,
        FIVE_WEEKS,
      ),
    ).toEqual(at(SPRING_SUNDAYS, "02:30:00", "03:30:00"));
    expect(
      drawnRow(
        rowOf("windows_timezone", "windows-fall@ics.test"),
        FALL_FROM,
        FIVE_WEEKS,
      ),
    ).toEqual(at(FALL_SUNDAYS, "01:30:00", "02:30:00"));
  });

  it("draws floating times as Toronto wall time", () => {
    expect(
      drawnRow(
        rowOf("floating", "floating-spring@ics.test"),
        SPRING_FROM,
        FIVE_WEEKS,
      ),
    ).toEqual(at(SPRING_SUNDAYS, "02:30:00", "03:30:00"));
    expect(
      drawnRow(
        rowOf("floating", "floating-fall@ics.test"),
        FALL_FROM,
        FIVE_WEEKS,
      ),
    ).toEqual(at(FALL_SUNDAYS, "01:30:00", "02:30:00"));
  });
});

describe("an imported calendar in the Europe/Paris zone", () => {
  // Disagreement "calendar zone dropped": 09:00 in Paris is drawn at 03:00 Toronto time every week. Paris changes
  // its clocks two weeks after Toronto does (2027-03-28 and 2027-10-31), so on 2027-03-14 and 2027-03-21, and on
  // 2027-10-31, the real time is 04:00 Toronto time.
  it("draws the series at the Toronto wall time of its first occurrence in every week", () => {
    const spring = rowOf("paris_tzid", "paris-spring@ics.test");
    expect(drawnRow(spring, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(SPRING_SUNDAYS, "03:00:00", "04:00:00"),
    );

    const fall = rowOf("paris_tzid", "paris-fall@ics.test");
    expect(drawnRow(fall, FALL_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-10-24", ...FALL_SUNDAYS], "03:00:00", "04:00:00"),
    );
  });
});

describe("an all-day imported series", () => {
  it("draws every Sunday as a whole day, the change day included", () => {
    const row = rowOf("all_day", "allday-spring@ics.test");
    expect(drawnRow(row, SPRING_FROM, FIVE_WEEKS)).toEqual(
      onDays(SPRING_SUNDAYS),
    );
  });

  it("leaves out the day excluded by a date", () => {
    const row = rowOf("all_day", "allday-fall@ics.test");
    expect(drawnRow(row, FALL_FROM, FIVE_WEEKS)).toEqual(
      onDays(["2027-10-31", "2027-11-14", "2027-11-21", "2027-11-28"]),
    );
  });
});

describe("an imported series with an exclusion in the hour the clocks repeat", () => {
  // Disagreement "repeated hour exclusion": whichever 01:30 the file excludes, the exclusion is sent as the wall
  // time 01:30 and the whole day goes.
  it.each(["exdate-utc", "exdate-first", "exdate-local"])(
    "draws %s without the change day",
    (name) => {
      const row = rowOf("exdate_repeated_hour", `${name}@ics.test`);
      expect(drawnRow(row, FALL_FROM, FIVE_WEEKS)).toEqual(
        at(
          ["2027-10-31", "2027-11-14", "2027-11-21", "2027-11-28"],
          "01:30:00",
          "02:30:00",
        ),
      );
    },
  );
});

describe("a modified instance of an imported series", () => {
  it("draws the series without the original date and the moved instance once", () => {
    const series = rowOf("recurrence_id_moved", "moved@ics.test");
    expect(drawnRow(series, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(
        ["2027-03-07", "2027-03-21", "2027-03-28", "2027-04-04"],
        "10:00:00",
        "11:00:00",
      ),
    );
    const moved = rowOf("recurrence_id_moved", "moved@ics.test_1805032800");
    expect(drawnRow(moved, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-03-15"], "14:00:00", "15:00:00"),
    );
  });
});

describe("a cancelled imported instance and a cancelled imported series", () => {
  // The instance cancelled for 2027-03-14 is only an exclusion of its series (the feed sends no event of its own for
  // it), and the cancelled series is not sent at all.
  it("leaves the cancelled instance's day out", () => {
    const series = rowOf("recurrence_id_cancelled", "cancelled@ics.test");
    expect(drawnRow(series, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(
        ["2027-03-07", "2027-03-21", "2027-03-28", "2027-04-04"],
        "10:00:00",
        "11:00:00",
      ),
    );
    expect(feedRows.recurrence_id_cancelled.map((row) => row.id)).toEqual([
      "cancelled@ics.test",
    ]);
  });
});

describe("an imported series with an end", () => {
  it("includes the day a date UNTIL names", () => {
    const row = rowOf("until", "until-date@ics.test");
    expect(drawnRow(row, SPRING_FROM, FIVE_WEEKS)).toEqual(
      onDays(["2027-03-07", "2027-03-14", "2027-03-21", "2027-03-28"]),
    );
  });

  it("includes the occurrence a UTC UNTIL names", () => {
    const spring = rowOf("until", "until-utc@ics.test");
    expect(drawnRow(spring, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-03-07", "2027-03-14", "2027-03-21"], "10:00:00", "11:00:00"),
    );
    const fall = rowOf("until", "until-utc-fall@ics.test");
    expect(drawnRow(fall, FALL_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-10-31", "2027-11-07"], "01:30:00", "02:30:00"),
    );
  });

  it("stops after the COUNT, drawing the change day at its wall time", () => {
    const spring = rowOf("count", "count-spring@ics.test");
    expect(drawnRow(spring, SPRING_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-03-07", "2027-03-14", "2027-03-21"], "02:30:00", "03:30:00"),
    );
    const fall = rowOf("count", "count-fall@ics.test");
    expect(drawnRow(fall, FALL_FROM, FIVE_WEEKS)).toEqual(
      at(["2027-10-31", "2027-11-07", "2027-11-14"], "01:30:00", "02:30:00"),
    );
  });
});

describe("an imported series with BYSETPOS", () => {
  // The browser honours BYSETPOS. The server's engine does not (disagreement "BYSETPOS ignored by the server",
  // pinned in calendar_helper_ics_dst_spec.rb), so these are the draws the server has to reproduce before
  // imported calendars move to it.
  it("draws the last weekday of each month", () => {
    const row = rowOf("bysetpos", "last-weekday@ics.test");
    expect(drawnRow(row, "2027-02-14", 77)).toEqual(
      at(["2027-02-26", "2027-03-31", "2027-04-30"], "09:00:00", "10:00:00"),
    );
  });

  it("draws the second Sunday of March at 02:30, the skipped hour", () => {
    const row = rowOf("bysetpos", "second-sunday-march@ics.test");
    expect(drawnRow(row, "2027-02-14", 77)).toEqual(
      at(["2027-02-14", "2027-03-14", "2027-04-11"], "02:30:00", "03:30:00"),
    );
  });

  it("draws the first Sunday of November at 01:30 once", () => {
    const row = rowOf("bysetpos", "first-sunday-november@ics.test");
    expect(drawnRow(row, "2027-10-03", 77)).toEqual(
      at(["2027-10-03", "2027-11-07", "2027-12-05"], "01:30:00", "02:30:00"),
    );
  });
});

describe("a series whose length spans the clocks going forward", () => {
  // Disagreement "timed series length across a clock change": the feeds send the length as 7 200 000 ms. The
  // browser adds it to the wall time, so the 01:00 occurrence of 2027-03-14 is drawn from 01:00 to 03:00, one real
  // hour. Measured in real time, as the server's expansion does, it ends at 04:00 daylight time.
  it("draws 01:00 to 03:00 on the change day, one real hour long", () => {
    const row = {
      id: "night",
      allDay: false,
      rrule: "DTSTART:20270307T010000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      duration: 7200000,
    };
    expect(drawnRow(row, "2027-03-07", 14)).toEqual(
      at(["2027-03-07", "2027-03-14", "2027-03-21"], "01:00:00", "03:00:00"),
    );
  });
});
