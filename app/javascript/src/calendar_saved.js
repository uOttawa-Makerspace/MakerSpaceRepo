import { Turbo } from "@hotwired/turbo-rails";

// What a calendar dialog's Turbo Stream answer ends with: the calendar on the
// page closes the dialog and fetches its events again.
Turbo.StreamActions.calendar_saved = function () {
  document.dispatchEvent(new CustomEvent("calendar:saved"));
};
