import { describe, expect, it } from "vitest";
import {
  editableUnavailability,
  keepFeedRule,
} from "../../../app/javascript/src/unavailability_event.js";

describe("keepFeedRule", () => {
  it("copies the rule text of a repeating entry into its extended properties", () => {
    const raw = {
      id: 1,
      rrule: "DTSTART:20270315T140000\nRRULE:FREQ=DAILY",
      extendedProps: { description: "d" },
    };
    const kept = keepFeedRule(raw);
    expect(kept.rrule).toBe(raw.rrule);
    expect(kept.extendedProps).toEqual({ description: "d", rrule: raw.rrule });
    expect(raw.extendedProps).toEqual({ description: "d" });
  });

  it("copes with a repeating entry without extended properties", () => {
    expect(keepFeedRule({ rrule: "R" }).extendedProps).toEqual({ rrule: "R" });
  });

  it("returns an entry that does not repeat as it is", () => {
    const raw = { id: 2, extendedProps: {} };
    expect(keepFeedRule(raw)).toBe(raw);
  });
});

describe("editableUnavailability", () => {
  const event = (extendedProps) => ({
    id: "31",
    title: "Lecture",
    allDay: true,
    startStr: "2027-03-17",
    endStr: "2027-03-18",
    extendedProps,
  });

  it("builds a plain object from the public event properties", () => {
    const entry = editableUnavailability(
      event({
        description: "Calculus",
        rrule: "R",
        eventType: "unavailability",
      }),
    );
    expect(entry).toEqual({
      id: "31",
      title: "Lecture",
      description: "Calculus",
      allDay: true,
      startStr: "2027-03-17",
      endStr: "2027-03-18",
      rrule: "R",
    });
  });

  it("uses an empty description and no rule when the feed sent none", () => {
    const entry = editableUnavailability(event({ description: null }));
    expect(entry.description).toBe("");
    expect(entry.rrule).toBeNull();
  });
});
