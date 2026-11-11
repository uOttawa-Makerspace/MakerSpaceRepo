// The staff unavailability dialog works from plain objects, not from the
// calendar's event objects.

// Keeps the rule text of a repeating entry where the calendar's public event
// API can read it: the calendar turns the feed's rrule field into its own
// internal rule and does not hand the text back, so it is copied into the
// extended properties as the feed event is read.
export function keepFeedRule(raw) {
  if (!raw.rrule) return raw;
  return { ...raw, extendedProps: { ...raw.extendedProps, rrule: raw.rrule } };
}

// What the dialog needs to edit an entry: id, title, description, all-day flag,
// the calendar's start and end strings (Toronto time) and the rule text of a
// repeating entry (null for a single one).
export function editableUnavailability(event) {
  return {
    id: event.id,
    title: event.title,
    description: event.extendedProps.description || "",
    allDay: event.allDay,
    startStr: event.startStr,
    endStr: event.endStr,
    rrule: event.extendedProps.rrule || null,
  };
}
