// The staff unavailability dialog works from plain objects, not from the
// calendar's event objects.

// What the dialog needs to edit an occurrence: the record id, title,
// description, all-day flag, the calendar's start and end strings (Toronto
// time), the occurrence's start instant as the server sent it, and what the
// server sent of the series' repeat (null for a single entry).
export function editableUnavailability(event) {
  const { recordId, description, occurrenceStart, series } =
    event.extendedProps;
  return {
    id: recordId,
    title: event.title,
    description: description || "",
    allDay: event.allDay,
    startStr: event.startStr,
    endStr: event.endStr,
    occurrenceStart,
    series: series || null,
  };
}
