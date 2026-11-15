import "flatpickr";

import { AccessorController } from "../src/accessor_controller.js";
import { csrfHeaders } from "../src/csrf";
import { DATE_TIME, flatpickrOptions } from "../src/page_locale.js";
import {
  failureText,
  parseBody,
  requestJson,
  requestResult,
  resultError,
} from "../src/request_error";

const JSON_TYPE = "application/json";
const JSON_HEADERS = { "Content-Type": JSON_TYPE, Accept: JSON_TYPE };

// The codes the server puts before the message of a booking rule (duration, slot).
const RULE_CODES = ["DurationHour", "DurationWeek", "TimeSlot"];

// The booking modal and its form: a new booking (from the calendar's Book
// button or a selected range) or a booking clicked on the calendar, which it
// saves, updates or deletes with JSON requests. A save that worked closes the
// modal and draws the calendar again; a refusal is shown on the form or in the
// page's toast.
export default class extends AccessorController {
  // prettier-ignore
  static targets = [
    "title", "id", "name", "description", "start", "end", "endValidation",
    "subspace", "recurring", "recurringField", "recurringEnd", "recurringType",
    "blocking", "submit", "part", "feedback",
  ];
  static values = { mode: String };
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

  // The backdrop sits in the page body, so it goes with the modal.
  disconnect() {
    this.pickers().forEach((picker) => picker.destroy());
    this.backdrop.remove();
  }

  pickers() {
    return [this.startPicker, this.endPicker, this.recurringEndPicker];
  }

  // The callback, unless the modal has left the page by the time it runs
  // (the user went on before the server answered).
  whileOnPage(callback) {
    return (value) => this.element.isConnected && callback(value);
  }

  get toast() {
    return this.bookingToastOutlet;
  }

  // The modal shows a new booking ("new"), a booking ("edit") or a booking of a
  // series ("series"); each part lists the modes it shows in, in data-modes.
  showMode(mode) {
    this.modeValue = mode;
    this.titleTarget.innerText =
      mode === "new" ? "New Booking" : "Update Booking";
    this.partTargets.forEach(
      (part) => (part.hidden = !part.dataset.modes.split(" ").includes(mode)),
    );
    this.toggleRecurring();
  }

  // A new booking, of the range selected on the calendar when there is one.
  openNew(range) {
    this.showMode("new");
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
    this.idTarget.value = event.id.split("_")[1];
    this.fetchBooking(this.idTarget.value)
      .then(this.whileOnPage((booking) => this.fill(booking)))
      .catch(
        this.whileOnPage((error) =>
          this.toast.show(
            "unavailableTitle",
            failureText(error, this.toast.text("unavailable")),
          ),
        ),
      );
  }

  // The booking lookup answers JSON only to staff; anything else (a refusal
  // redirected to an HTML page, a server error) is shown as the server's reason, not parsed.
  fetchBooking(id) {
    return requestJson(
      `/sub_space_booking/get_sub_space_booking?id=${encodeURIComponent(id)}`,
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
    this.subspaceTarget.value = booking.sub_space_id;
    this.showMode(booking.recurring_booking_id == null ? "edit" : "series");
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
    this.submitTargets.forEach((button) => button.removeAttribute("disabled"));
    this.feedbackTargets.forEach((feedback) => feedback.remove());
    this.element
      .querySelectorAll(".is-invalid")
      .forEach((field) => field.classList.remove("is-invalid"));
    this.endValidationTarget.classList.add("d-none");
  }

  toggleRecurring() {
    const recurring = this.recurringTarget.checked;
    this.recurringFieldTargets.forEach((field) => (field.hidden = !recurring));
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

  // The request of the pressed button, from its action params: the method and
  // the url, where ":id" stands for the booking's id, and the name of the
  // page's text to show once the save worked. A save checks the dates first,
  // sends the booking and disables its button while it runs; a delete sends
  // no body.
  request({ currentTarget, params: { method, url, success } }) {
    const id = encodeURIComponent(this.idTarget.value);
    const path = url.replaceAll(":id", id);
    if (method === "DELETE") return this.send(method, path);
    if (!this.datesValid()) return;
    const booking =
      method === "POST"
        ? this.newBooking()
        : this.payload(this.subspaceTarget.value);
    const successText = success && this.toast.text(success);
    this.send(method, path, currentTarget, booking, successText);
  }

  // A new booking is in the room the address names, and may start a series.
  newBooking() {
    return this.payload(
      new URLSearchParams(window.location.search).get("room"),
      {
        recurring: this.recurringTarget.checked,
        recurring_end: this.recurringEndPicker.selectedDates[0],
        recurring_frequency: this.recurringTypeTarget.value,
      },
    );
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
      .then(this.whileOnPage((r) => this.showAnswer(r, button, successText)))
      .catch(
        this.whileOnPage((error) =>
          this.showFailure(button, failureText(error)),
        ),
      );
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
    feedback.dataset.bookingModalTarget = "feedback";
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
