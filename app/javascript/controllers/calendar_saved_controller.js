import { Controller } from "@hotwired/stimulus";

// Stimulus defines the outlet accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  adminCalendarOutlets: { saved(): void }[],
  unavailabilitiesCalendarOutlets: { saved(): void }[],
}} */ (/** @type {unknown} */ (Controller));

// The marker a calendar dialog's Turbo Stream answer leaves on the page: it
// tells the calendar of the page that the dialog saved (the calendar closes it
// and fetches its events again), then removes itself.
export default class extends TypedController {
  static outlets = ["admin-calendar", "unavailabilities-calendar"];

  connect() {
    [
      ...this.adminCalendarOutlets,
      ...this.unavailabilitiesCalendarOutlets,
    ].forEach((calendar) => calendar.saved());
    this.element.remove();
  }
}
