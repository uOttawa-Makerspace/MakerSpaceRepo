import { RRule } from "rrule";

/*
 * Recurrence rules are kept in Toronto wall-clock time: "Monday 9:00" stays
 * 9:00 whatever the clock offset on the day. Everything here works on wall
 * times written as numbers: the milliseconds since 1970-01-01T00:00 of the
 * wall-clock fields read as if they were UTC (a "wall time"), so nothing
 * depends on the zone of the browser. A real instant appears only at the
 * edges (`wallToInstant`, `instantToWall`). The server expands repeat rules
 * (RecurringSeries); this module only writes them (`storedRule`).
 */

const ZONE = "America/Toronto";
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

const wallFields = new Intl.DateTimeFormat("en-CA", {
  timeZone: ZONE,
  hourCycle: "h23",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

export function instantToWall(instantMs) {
  const part = {};
  for (const { type, value } of wallFields.formatToParts(instantMs)) {
    part[type] = Number(value);
  }
  return Date.UTC(
    part.year,
    part.month - 1,
    part.day,
    part.hour,
    part.minute,
    part.second,
  );
}

function offsetAt(instantMs) {
  return instantToWall(instantMs) - Math.floor(instantMs / 1000) * 1000;
}

/*
 * The instant of a Toronto wall time. A time skipped by the clocks going
 * forward (2:30) is read with the offset from before the change, which gives
 * the same instant as 3:30. A time that happens twice when the clocks go back
 * (1:30) is the first one.
 */
export function wallToInstant(wallMs) {
  const candidates = [wallMs - DAY_MS, wallMs + DAY_MS].map(
    (nearby) => wallMs - offsetAt(nearby),
  );
  const real = candidates.filter((c) => instantToWall(c) === wallMs);
  return real.length > 0 ? Math.min(...real) : candidates[0];
}

/* "2026-03-30T09:30" or "2026-03-30T09:30:00" as a wall time. */
export function wallFromString(value) {
  return Date.parse(`${value.slice(0, 19).padEnd(19, ":00")}Z`);
}

/* The wall time in a datetime-local form field; an empty field is now. */
export function wallOfField(value) {
  return value ? wallFromString(value) : instantToWall(Date.now());
}

/* A wall time as a datetime-local field value ("2026-03-30T09:30"). */
export function fieldValue(wallMs) {
  return new Date(wallMs).toISOString().slice(0, 16);
}

/* A wall time as a date field value ("2026-03-30"). */
export function dateValue(wallMs) {
  return fieldValue(wallMs).slice(0, 10);
}

/*
 * The wall end of a timed calendar entry: its own, or one wall-clock hour after
 * the start when the calendar gives none (it drops an end equal to the start:
 * one real hour from the first 1:30 of the night the clocks go back).
 */
export function wallEnd(endStr, startWall) {
  return endStr ? wallFromCalendar(endStr) : startWall + HOUR_MS;
}

/* The wall time at midnight starting the day of a wall time. */
export function startOfDay(wallMs) {
  return wallMs - (wallMs % DAY_MS);
}

const hasOffset = (value) => /(Z|[+-]\d{2}:\d{2})$/.test(value);

/*
 * The wall time of a date the calendar gives. One with an offset (or Z) is an
 * instant. One without is already Toronto wall-clock time: the calendars draw
 * in Toronto. A date alone is its midnight.
 */
export function wallFromCalendar(value) {
  if (hasOffset(value)) return instantToWall(Date.parse(value));
  return wallFromString(value.includes("T") ? value : `${value}T00:00`);
}

/*
 * The instant of a date the calendar gives, read as wallFromCalendar reads it.
 * One with an offset keeps its own instant, so the second 1:30 of the night
 * the clocks go back stays the second one.
 */
export function instantFromCalendar(value) {
  if (hasOffset(value)) return Date.parse(value);
  return wallToInstant(wallFromCalendar(value));
}

/* The instant a series repeating until `date` ("2026-03-30") ends: the last second of that day. */
export function endOfDateInstant(date) {
  return wallToInstant(wallFromString(`${date}T23:59:59`));
}

function stampOf(wallMs) {
  return new Date(wallMs).toISOString().replace(/[-:]|\.\d+Z/g, "");
}

/*
 * A repeat rule as it is stored: the start as Toronto wall-clock time
 * (DTSTART;TZID=America/Toronto), so the series keeps its clock time across
 * clock changes, and the repeat end as the instant of the last second of
 * `untilDate` ("2026-03-30") in Toronto, a UTC stamp. `options` are the other
 * rrule.js options (freq, byweekday).
 */
export function storedRule(options, startWall, untilDate) {
  const until = untilDate ? new Date(endOfDateInstant(untilDate)) : null;
  const body = new RRule({ ...options, until }).toString();
  // A time the clocks skip or repeat is written as the time it stands for
  const start = stampOf(instantToWall(wallToInstant(startWall)));
  return `DTSTART;TZID=${ZONE}:${start}\n${body}`;
}
