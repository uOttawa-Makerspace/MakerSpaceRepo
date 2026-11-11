import { RRule, rrulestr } from "rrule";

/*
 * Recurrence rules are kept in Toronto wall-clock time: "Monday 9:00" stays
 * 9:00 whatever the clock offset on the day. Everything here works on wall
 * times written as numbers: the milliseconds since 1970-01-01T00:00 of the
 * wall-clock fields read as if they were UTC (a "wall time"). Every day is then
 * exactly 24 hours long, which is what rrule.js (it has no time zones) needs,
 * and nothing depends on the zone of the browser.
 *
 * A real instant appears only at the edges: a timestamp ending in Z inside a
 * rule is turned into Toronto wall fields, and `wallToInstant` turns a wall
 * time back into an instant for display.
 */

const ZONE = "America/Toronto";
const DAY_MS = 24 * 60 * 60 * 1000;

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

function utcStampToWallStamp(stamp) {
  const [, y, mo, d, h, mi, s] = stamp.match(
    /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/,
  );
  return stampOf(instantToWall(Date.UTC(y, mo - 1, d, h, mi, s)));
}

// Timestamps ending in Z (an UNTIL or EXDATE written by the rule builder)
// are instants: read them in Toronto. A start written in Toronto time
// (DTSTART;TZID=America/Toronto:...) is already a wall time.
const ZONED_START = new RegExp(`^DTSTART;TZID=${ZONE}:`, "m");

function toWallRule(ruleText) {
  return ruleText
    .replace(ZONED_START, "DTSTART:")
    .replace(/(\d{8}T\d{6})Z/g, (_, stamp) => utcStampToWallStamp(stamp));
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

/* The rule with its start replaced by a wall time. */
export function startingAt(ruleText, startWall) {
  const lines = ruleText.split("\n").filter((l) => !l.startsWith("DTSTART"));
  return [`DTSTART:${stampOf(startWall)}`, ...lines].join("\n");
}

function overlaps(occurrence, from, to) {
  return occurrence.start < to && occurrence.end > from;
}

/*
 * The occurrences of a rule that overlap the wall-time range [from, to), each
 * ending `durationMs` of wall-clock time after it starts. The rule is read once.
 */
export function occurrencesOverlapping(ruleText, durationMs, from, to) {
  const rule = rrulestr(toWallRule(ruleText));
  const until = rule.options.until;
  if (until && until.getTime() < from - durationMs) return [];
  return rule
    .between(new Date(from - durationMs), new Date(to), true)
    .map((start) => ({
      start: start.getTime(),
      end: start.getTime() + durationMs,
    }))
    .filter((occurrence) => overlaps(occurrence, from, to));
}

/*
 * The intervals of a calendar feed entry that overlap the wall-time range
 * [from, to). An entry is either one-off ({ start, end }) or repeating
 * ({ rrule, duration }, the duration absent for a series with no end); its times are Toronto wall-clock strings. A rule that
 * cannot be read has none. A repeating entry is parsed and expanded once, for
 * the whole range.
 */
export function entryIntervals(entry, from, to) {
  if (!entry.rrule) {
    const occurrence = {
      start: wallFromString(entry.start),
      end: wallFromString(entry.end),
    };
    return overlaps(occurrence, from, to) ? [occurrence] : [];
  }
  try {
    // a series with no end has no duration: each occurrence is a single moment
    return occurrencesOverlapping(entry.rrule, entry.duration ?? 0, from, to);
  } catch (error) {
    console.warn("Invalid RRULE:", error);
    return [];
  }
}
