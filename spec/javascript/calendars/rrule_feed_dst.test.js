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
