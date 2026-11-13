import { describe, expect, it } from "vitest";
import { editableUnavailability } from "../../../app/javascript/src/unavailability_event.js";

describe("editableUnavailability", () => {
  const event = (extendedProps) => ({
    id: "31@1805202000",
    title: "Lecture",
    allDay: true,
    startStr: "2027-03-17",
    endStr: "2027-03-18",
    extendedProps,
  });

  it("builds a plain object from the public event properties and what the feed sent", () => {
    const series = { frequency: "WEEKLY", weekdays: ["WE"], until: null };
    const entry = editableUnavailability(
      event({
        description: "Calculus",
        eventType: "unavailability",
        recordId: 31,
        occurrenceStart: "2027-03-17T04:00:00Z",
        series,
      }),
    );
    expect(entry).toEqual({
      id: 31,
      title: "Lecture",
      description: "Calculus",
      allDay: true,
      startStr: "2027-03-17",
      endStr: "2027-03-18",
      occurrenceStart: "2027-03-17T04:00:00Z",
      series,
    });
  });

  it("uses an empty description and no series when the feed sent none", () => {
    const entry = editableUnavailability(event({ description: null }));
    expect(entry.description).toBe("");
    expect(entry.series).toBeNull();
  });
});
