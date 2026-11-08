import { rrulestr } from "rrule";

/*
 * Recurrence rules arrive in wall-clock time: the start is "Monday 9:00",
 * whatever the clock offset on the day. rrule.js has no time zones, so it is
 * given the wall-clock fields as if they were UTC (every day is then exactly
 * 24 hours long), and each occurrence is turned back into a local Date from
 * its fields. A timestamp that ends in Z (an UNTIL or EXDATE written by the
 * rule builder, or the start of a rule built in the browser) is an instant;
 * it is first rewritten as the local wall-clock fields of that instant.
 */

const UTC_STAMP = /(\d{8}T\d{6})Z/g;

const pad = (n) => String(n).padStart(2, "0");

function wallStamp(date) {
  return (
    `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}` +
    `T${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`
  );
}

function parseUtcStamp(stamp) {
  const [, y, mo, d, h, mi, s] = stamp.match(
    /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/,
  );
  return new Date(Date.UTC(y, mo - 1, d, h, mi, s));
}

function toWallRule(ruleText) {
  return ruleText.replace(UTC_STAMP, (_, stamp) =>
    wallStamp(parseUtcStamp(stamp)),
  );
}

function wallAsUtc(date) {
  return new Date(
    Date.UTC(
      date.getFullYear(),
      date.getMonth(),
      date.getDate(),
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
    ),
  );
}

function utcFieldsAsLocal(date) {
  return new Date(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
    date.getUTCHours(),
    date.getUTCMinutes(),
    date.getUTCSeconds(),
  );
}

function overlaps(occurrence, from, to) {
  return occurrence.start < to && occurrence.end > from;
}

/*
 * The occurrences of a rule that overlap [from, to), as local Dates with the
 * end of each one `durationMs` after its start.
 */
export function occurrencesOverlapping(ruleText, durationMs, from, to) {
  const rule = rrulestr(toWallRule(ruleText));
  const searchFrom = new Date(from.getTime() - durationMs);
  return rule
    .between(wallAsUtc(searchFrom), wallAsUtc(to), true)
    .map((utcFields) => {
      const start = utcFieldsAsLocal(utcFields);
      return { start, end: new Date(start.getTime() + durationMs) };
    })
    .filter((occurrence) => overlaps(occurrence, from, to));
}

/*
 * Whether a calendar feed entry overlaps [from, to). An entry is either
 * one-off ({ start, end }) or repeating ({ start, rrule, duration }); its
 * times are local wall-clock strings. A rule that cannot be read overlaps
 * nothing.
 */
export function entryOverlaps(entry, from, to) {
  const start = new Date(entry.start);
  if (!entry.rrule) {
    return overlaps({ start, end: new Date(entry.end) }, from, to);
  }
  try {
    return (
      occurrencesOverlapping(entry.rrule, entry.duration, from, to).length > 0
    );
  } catch (error) {
    console.warn("Invalid RRULE:", error);
    return false;
  }
}
