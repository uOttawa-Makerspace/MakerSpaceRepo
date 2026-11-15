import { Controller } from "@hotwired/stimulus";
import "flatpickr";

import { csrfHeaders } from "../src/csrf";
import { DATE_TIME, flatpickrOptions } from "../src/page_locale.js";
import {
  failureText,
  parseBody,
  requestJson,
  requestResult,
  resultError,
} from "../src/request_error";

/** @typedef {HTMLInputElement & { flatpickr(options: object): any }} PickerInput */

// Stimulus defines the target and outlet accessors at runtime; this tells the
// type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  titleTarget: HTMLElement, endValidationTarget: HTMLElement,
  idTarget: HTMLInputElement, nameTarget: HTMLInputElement, descriptionTarget: HTMLInputElement,
  startTarget: PickerInput, endTarget: PickerInput, recurringEndTarget: PickerInput,
  subspaceTarget: HTMLSelectElement, recurringTypeTarget: HTMLSelectElement,
  recurringTarget: HTMLInputElement, blockingTarget: HTMLInputElement, hasBlockingTarget: boolean,
  saveTarget: HTMLButtonElement, updateTarget: HTMLButtonElement,
  bookingCalendarOutlet: { refetch(): void },
  bookingToastOutlet: { text(name: string): string, show(titleName: string, text: string, success?: boolean): void },
}} */ (/** @type {unknown} */ (Controller));

const JSON_TYPE = "application/json";
const JSON_HEADERS = { "Content-Type": JSON_TYPE, Accept: JSON_TYPE };

// The codes the server puts before the message of a booking rule (duration, slot).
const RULE_CODES = ["DurationHour", "DurationWeek", "TimeSlot"];

// The booking modal and its form: a new booking (from the calendar's Book
// button or a selected range) or a booking clicked on the calendar, which it
// saves, updates or deletes with JSON requests. A save that worked closes the
// modal and draws the calendar again; a refusal is shown on the form or in the
// page's toast.
export default class extends TypedController {
  // prettier-ignore
  static targets = [
    "title", "id", "name", "description", "start", "end", "endValidation",
    "subspace", "subspaceLabel", "recurring", "recurringLabel", "recurringField",
    "recurringEnd", "recurringType", "blocking", "save", "update", "delete",
    "deleteSeries",
  ];
  static outlets = ["booking-calendar", "booking-toast"];

  connect() {
    const picker = (input, options, format) =>
      input.flatpickr(flatpickrOptions(this.element, options, format));
    this.startPicker = picker(this.startTarget, DATE_TIME, "date_time");
    this.endPicker = picker(this.endTarget, DATE_TIME, "date_time");
    const date = { enableTime: false, altInput: true };
    this.recurringEndPicker = picker(this.recurringEndTarget, date, "date");
    this.backdrop = Object.assign(
      this.element.ownerDocument.createElement("div"),
      { id: "book-modal-backdrop", className: "modal-backdrop fade show" },
    );
  }

  get toast() {
    return this.bookingToastOutlet;
  }

  // Shows every target of those names (space-separated) with that display.
  show(display, names) {
    const elements = /** @type {HTMLElement[]} */ (
      names.split(" ").flatMap((name) => this.targets.findAll(name))
    );
    elements.forEach((el) => (el.style.display = display));
  }

  // A new booking, of the range selected on the calendar when there is one.
  openNew(range) {
    this.show("block", "save");
    this.show("none", "update subspace subspaceLabel delete deleteSeries");
    this.show("inline-block", "recurring recurringLabel");
    this.titleTarget.innerText = "New Booking";
    this.toggleRecurring();
    this.open();
    if (range) {
      this.startPicker.setDate(Date.parse(range.startStr));
      this.endPicker.setDate(Date.parse(range.endStr));
    }
    this.nameTarget.focus();
  }

  // A booking clicked on the calendar, when the user may see it: the modal
  // opens once its details came from the server.
  openBooking(event) {
    if (!event.extendedProps.viewable) return;
    this.show("none", "save recurring recurringLabel");
    this.show("block", "update subspace subspaceLabel");
    this.titleTarget.innerText = "Update Booking";
    this.idTarget.value = event.id.split("_")[1];
    this.fetchBooking(this.idTarget.value)
      .then((booking) => this.fill(booking))
      .catch((error) =>
        this.toast.show(
          "unavailableTitle",
          failureText(error, this.toast.text("unavailable")),
        ),
      );
  }

  // The booking lookup answers JSON only to staff; anything else (a refusal
  // redirected to an HTML page, a server error) is shown as the server's reason, not parsed.
  fetchBooking(id) {
    return requestJson(
      `/sub_space_booking/get_sub_space_booking?id=${id}`,
      { headers: JSON_HEADERS },
      { fallback: this.toast.text("unavailable"), requireBody: true },
    );
  }

  // A booking of a series is deleted on its own or with the rest of the series.
  fill(booking) {
    this.nameTarget.value = booking.name;
    this.descriptionTarget.value = booking.description;
    this.startPicker.setDate(Date.parse(booking.start_time.slice(0, -6)));
    this.endPicker.setDate(Date.parse(booking.end_time.slice(0, -6)));
    this.recurringTarget.checked = false;
    if (this.hasBlockingTarget) this.blockingTarget.checked = booking.blocking;
    const series = booking.recurring_booking_id != null;
    this.show(series ? "none" : "block", "delete");
    this.show(series ? "block" : "none", "deleteSeries");
    this.subspaceTarget.value = booking.sub_space_id;
    this.toggleRecurring();
    this.open();
  }

  // The modal is drawn over a backdrop of its own. Like Bootstrap's, it belongs
  // to the page body, over everything else on the page.
  open() {
    this.element.style.display = "block";
    this.element.classList.add("show");
    this.element.ownerDocument.body.append(this.backdrop);
  }

  // Closing empties the form and clears what it showed.
  close() {
    this.element.style.display = "none";
    this.element.classList.remove("show");
    this.backdrop.remove();
    this.nameTarget.value = "";
    this.descriptionTarget.value = "";
    this.recurringEndPicker.setDate(null);
    this.saveTarget.removeAttribute("disabled");
    this.updateTarget.removeAttribute("disabled");
    this.element
      .querySelectorAll(".is-invalid")
      .forEach((el) => el.classList.remove("is-invalid"));
    this.element
      .querySelectorAll(".invalid-feedback")
      .forEach((el) => el !== this.endValidationTarget && el.remove());
    this.endValidationTarget.classList.add("d-none");
  }

  toggleRecurring() {
    this.show(
      this.recurringTarget.checked ? "block" : "none",
      "recurringField",
    );
  }

  // The end must come after the start; the end field says so when it does not.
  datesValid() {
    const [start] = this.startPicker.selectedDates;
    const [end] = this.endPicker.selectedDates;
    const valid = !(start && end && start >= end);
    this.endValidationTarget.classList.toggle("d-none", valid);
    this.endPicker.altInput.classList.toggle("is-invalid", !valid);
    return valid;
  }

  // The booking as the server takes it, its fields in the server's order.
  payload(subSpaceId, recurrence = {}) {
    return {
      sub_space_booking: {
        name: this.nameTarget.value,
        description: this.descriptionTarget.value,
        start_time: this.startPicker.input.value,
        end_time: this.endPicker.input.value,
        sub_space_id: subSpaceId,
        ...recurrence,
        blocking: this.hasBlockingTarget && this.blockingTarget.checked,
      },
    };
  }

  // A new booking is in the room the address names.
  book() {
    if (!this.datesValid()) return;
    const room = new URLSearchParams(window.location.search).get("room");
    this.send(
      "POST",
      "/sub_space_booking",
      this.saveTarget,
      this.payload(room, {
        recurring: this.recurringTarget.checked,
        recurring_end: this.recurringEndPicker.selectedDates[0],
        recurring_frequency: this.recurringTypeTarget.value,
      }),
    );
  }

  update() {
    if (!this.datesValid()) return;
    this.send(
      "PATCH",
      `/sub_space_booking/${this.idTarget.value}/update`,
      this.updateTarget,
      this.payload(this.subspaceTarget.value),
      this.toast.text("updated"),
    );
  }

  delete() {
    const id = this.idTarget.value;
    this.send("DELETE", `/sub_space_booking/${id}/delete/${id}`);
  }

  deleteRest() {
    const id = this.idTarget.value;
    this.send("DELETE", `/sub_space_booking/${id}/delete_remaining_recurring`);
  }

  // A JSON request with the CSRF token; a delete has no data, so no body. The
  // button is disabled while it runs, and successText, when given, is shown
  // once the save worked.
  send(method, url, button, data, successText = "") {
    button?.setAttribute("disabled", "");
    const request = new Request(url, {
      method,
      headers: csrfHeaders(JSON_HEADERS),
      body: JSON.stringify(data),
    });
    requestResult(request)
      .then((result) => this.showAnswer(result, button, successText))
      .catch((error) => this.showFailure(button, failureText(error)));
  }

  showAnswer(result, button, successText) {
    const answer = parseBody(result.text);
    if (answer?.errors) this.showErrorList(answer, button);
    else if (result.ok) this.showSaved(answer, successText);
    else this.showFailure(button, resultError(result));
  }

  // A failure with no per-field errors (no answer, a server error, a missing
  // record): say why, and keep the form.
  showFailure(button, text) {
    button?.removeAttribute("disabled");
    this.toast.show("failedTitle", text);
  }

  // Success: close the modal and reload the calendar data, or the whole page
  // when the answer was not JSON (a hard redirect).
  showSaved(answer, successText) {
    this.close();
    this.bookingCalendarOutlet.refetch();
    if (successText) this.toast.show("updatedTitle", successText, true);
    if (answer === null) window.location.reload();
  }

  // The answer's list of coded errors. A partly booked recurring series
  // (errors with booked > 0) has some occurrences now, so show the calendar and
  // say what happened rather than reporting a plain failure (the user would
  // rebook and create duplicates).
  showErrorList(answer, button) {
    if (answer.booked > 0) {
      this.bookingCalendarOutlet.refetch();
      this.closeWithToast("partlyDoneTitle", answer.summary);
      return;
    }
    button?.removeAttribute("disabled");
    for (const error of answer.errors) this.showCodedError(error);
  }

  // "<Code> <message>": a booking rule (duration, slot) is a toast that closes
  // the modal; an error about a field marks the field "book-<code>" once; any
  // other error (a refused block) is a toast that keeps the modal open.
  showCodedError(error) {
    const [code, ...rest] = error.split(" ");
    const message = rest.join(" ");
    if (RULE_CODES.includes(code))
      return this.closeWithToast("failedTitle", message);
    const field = this.element.querySelector(
      `#${CSS.escape(`book-${code.toLowerCase()}`)}`,
    );
    if (!field) return this.toast.show("failedTitle", error);
    if (field.classList.contains("is-invalid")) return;
    const feedback = this.element.ownerDocument.createElement("div");
    feedback.className = "invalid-feedback";
    feedback.innerText = message || error;
    field.classList.add("is-invalid");
    field.after(feedback);
  }

  closeWithToast(titleName, text) {
    this.close();
    this.toast.show(titleName, text);
    window.scrollTo(0, 0);
  }
}
