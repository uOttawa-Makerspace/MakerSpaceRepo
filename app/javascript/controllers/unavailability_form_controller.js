import { Controller } from "@hotwired/stimulus";
import { Collapse, Modal } from "bootstrap";
import { RRule } from "rrule";

import {
  dateValue,
  fieldValue,
  instantFromCalendar,
  instantToWall,
  startOfDay,
  storedRule,
  wallFromCalendar,
  wallOfField,
  wallToInstant,
} from "../src/recurrence.js";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const COLLECTION_PATH = "/staff/unavailabilities";

const FREQUENCY_NAMES = new Map([
  [RRule.DAILY, "DAILY"],
  [RRule.WEEKLY, "WEEKLY"],
  [RRule.MONTHLY, "MONTHLY"],
]);

// Stimulus defines the target accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  exitMessageValue: string,
  allDayTarget: HTMLInputElement,
  startTimeTarget: HTMLInputElement,
  endTimeTarget: HTMLInputElement,
  timeErrorTarget: HTMLElement,
  frequencyTarget: HTMLSelectElement,
  optionsTarget: HTMLElement,
  untilTarget: HTMLInputElement,
  weeklyOptionsTarget: HTMLElement,
  dayCheckboxTargets: HTMLInputElement[],
  dayFreqErrorTarget: HTMLElement,
  utcStartTarget: HTMLInputElement,
  utcEndTarget: HTMLInputElement,
  ruleFieldTarget: HTMLInputElement,
  collapseTarget: HTMLElement,
  titleFieldTarget: HTMLInputElement,
  descriptionFieldTarget: HTMLTextAreaElement,
  labelTarget: HTMLElement,
  formTarget: HTMLFormElement,
  modalButtonsTarget: HTMLElement,
  saveButtonTarget: HTMLInputElement,
  updateDropdownTarget: HTMLElement,
  updateDropdownItemsTarget: HTMLElement,
  deleteFormsTarget: HTMLElement,
  deleteSingleFormTarget: HTMLFormElement,
  deleteFollowingFormTarget: HTMLFormElement,
  deleteAllFormTarget: HTMLFormElement,
  deleteStartDateTargets: HTMLInputElement[],
}} */ (/** @type {unknown} */ (Controller));

// The unavailability dialog (add and edit): opens in add, edit or range mode,
// validates the time range, handles all-day entries and repeat options, and
// sends the Toronto wall-clock times as instants with the stored recurrence
// rule when the form is submitted. It only reads and writes inside its own
// element.
export default class extends TypedController {
  static values = { exitMessage: String };

  static targets = [
    "allDay",
    "startTime",
    "endTime",
    "timeError",
    "frequency",
    "options",
    "until",
    "weeklyOptions",
    "dayCheckbox",
    "dayFreqError",
    "utcStart",
    "utcEnd",
    "ruleField",
    "collapse",
    "titleField",
    "descriptionField",
    "label",
    "form",
    "modalButtons",
    "saveButton",
    "updateDropdown",
    "updateDropdownItems",
    "deleteForms",
    "deleteSingleForm",
    "deleteFollowingForm",
    "deleteAllForm",
    "deleteStartDate",
  ];

  // ---------------------------------------
  // Opening the dialog
  // ---------------------------------------
  // The element given as returnFocusTo gets the focus back when the dialog
  // closes (the button that opened it).
  openForAdd({ returnFocusTo = null } = {}) {
    this.returnFocusTo = returnFocusTo;
    this.formTarget.action = COLLECTION_PATH;
    this.formTarget.querySelector('input[name="_method"]')?.remove();

    this.labelTarget.textContent = "Add Unavailability";
    this.saveButtonTarget.value = "Save";
    this.modalButtonsTarget.appendChild(this.saveButtonTarget);
    this.updateDropdownTarget.style.display = "none";

    this.modal.show();
  }

  // A range dragged on the calendar: the start and end are the calendar's
  // strings, which already hold Toronto time.
  openForRange({ start, end }) {
    this.openForAdd();
    this.startTimeTarget.value = fieldValue(wallFromCalendar(start));
    this.endTimeTarget.value = fieldValue(wallFromCalendar(end));
  }

  // The event is the calendar's: its id, times, title, description and, for a
  // repeating entry, the rule it was built from.
  openForEdit(calendarEvent) {
    const def = calendarEvent._def;
    const repeats = Boolean(def.recurringDef);

    this.modal.show();
    this.pointFormAt(calendarEvent.id);
    this.fillTimes(calendarEvent);
    this.titleFieldTarget.value = def.title || "";
    this.descriptionFieldTarget.value = def.extendedProps.description || "";
    this.restoreRule(def.recurringDef?.typeData?.rruleSet);

    this.labelTarget.textContent = "Edit Unavailability";
    this.saveButtonTarget.value = "Update";
    this.placeSaveButton(repeats);
    this.showDeleteChoices(calendarEvent, repeats);
  }

  get modal() {
    return Modal.getOrCreateInstance(this.element);
  }

  pointFormAt(id) {
    this.formTarget.action = `${COLLECTION_PATH}/${encodeURIComponent(id)}`;
    this.formTarget.querySelector('input[name="_method"]')?.remove();
    const methodInput = document.createElement("input");
    methodInput.type = "hidden";
    methodInput.name = "_method";
    methodInput.value = "patch";
    this.formTarget.appendChild(methodInput);
  }

  // The fields hold Toronto wall-clock times, like the calendar.
  fillTimes(calendarEvent) {
    if (calendarEvent.allDay) {
      this.allDayTarget.checked = true;
      const startDate = startOfDay(wallFromCalendar(calendarEvent.startStr));
      this.startTimeTarget.value = fieldValue(startDate);
      this.endTimeTarget.value = fieldValue(startDate + DAY_MS);
      this.endTimeTarget.disabled = true;
    } else {
      this.startTimeTarget.value = fieldValue(
        wallFromCalendar(calendarEvent.startStr),
      );
      this.endTimeTarget.value = fieldValue(
        wallFromCalendar(calendarEvent.endStr),
      );
    }
  }

  // Unbuilds the repeat rule of the feed into the repeat fields.
  restoreRule(ruleSet) {
    if (!ruleSet) return;

    const rule = new RRule(ruleSet._rrule[0].origOptions);
    const { freq, byweekday, until, dtstart } = rule.options;

    this.optionsTarget.style.display = "block";
    this.weeklyOptionsTarget.style.display = "none";
    this.restoreFrequency(freq, byweekday);

    const untilDate = until ? dateValue(until.getTime()) : "";
    this.untilTarget.value = untilDate;
    // The feed's start is a Toronto wall time already
    this.ruleFieldTarget.value = storedRule(
      { freq, byweekday },
      dtstart.getTime(),
      untilDate,
    );
  }

  restoreFrequency(freq, byweekday) {
    const name = FREQUENCY_NAMES.get(freq);
    if (name) this.frequencyTarget.value = name;
    if (freq !== RRule.WEEKLY) return;

    this.weeklyOptionsTarget.style.display = "block";
    byweekday.forEach((day) => {
      // rrule has MO=0 while we use SU=0...
      const box =
        this.dayCheckboxTargets[day + 1] || this.dayCheckboxTargets[0];
      box.checked = true;
    });
  }

  // A repeating entry saves through the "update this / all" menu.
  placeSaveButton(repeats) {
    if (repeats) {
      this.updateDropdownItemsTarget.appendChild(this.saveButtonTarget);
    } else {
      this.modalButtonsTarget.appendChild(this.saveButtonTarget);
    }
    this.updateDropdownTarget.style.display = repeats ? "block" : "none";
  }

  showDeleteChoices(calendarEvent, repeats) {
    const id = encodeURIComponent(calendarEvent.id);
    const path = `${COLLECTION_PATH}/${id}/delete_with_scope`;
    this.deleteScopeForms.forEach((form) => {
      form.action = path;
    });
    this.deleteFormsTarget.style.display = "flex";

    const display = repeats ? "block" : "none";
    this.deleteFollowingFormTarget.style.display = display;
    this.deleteAllFormTarget.style.display = display;

    // The instant of the clicked occurrence
    const occurrenceStart = new Date(
      instantFromCalendar(calendarEvent.startStr),
    ).toISOString();
    this.deleteStartDateTargets.forEach((input) => {
      input.value = occurrenceStart;
    });
  }

  get deleteScopeForms() {
    return [
      this.deleteSingleFormTarget,
      this.deleteFollowingFormTarget,
      this.deleteAllFormTarget,
    ];
  }

  // ---------------------------------------
  // Form events
  // ---------------------------------------
  // The form fields hold Toronto wall-clock times, like the calendar.
  validateTimeRange() {
    const startDate = wallOfField(this.startTimeTarget.value);
    const endDate = wallOfField(this.endTimeTarget.value);
    const valid = endDate > startDate;

    this.timeErrorTarget.classList.toggle("d-none", valid);
    this.saveButtonTarget.disabled = !valid;
    this.saveButtonTarget.classList.toggle("disabled", !valid);
  }

  startChanged() {
    if (this.allDayTarget.checked) this.snapToAllDay();
    this.validateTimeRange();
  }

  snapToAllDay() {
    const startDate = startOfDay(wallOfField(this.startTimeTarget.value));

    this.startTimeTarget.value = fieldValue(startDate);
    this.endTimeTarget.value = fieldValue(startDate + DAY_MS);
    this.endTimeTarget.disabled = true;

    if (this.frequencyTarget.value === "WEEKLY") {
      const dayIndex = new Date(startDate).getUTCDay();
      this.dayCheckboxTargets.forEach((checkbox, index) => {
        checkbox.checked = index === dayIndex;
      });
    }
  }

  allDayChanged() {
    if (this.allDayTarget.checked) {
      this.snapToAllDay();
    } else {
      this.endTimeTarget.disabled = false;
      const start = wallToInstant(wallOfField(this.startTimeTarget.value));
      this.endTimeTarget.value = fieldValue(instantToWall(start + HOUR_MS));
    }
    this.validateTimeRange();
  }

  frequencyChanged() {
    const freq = this.frequencyTarget.value;
    this.optionsTarget.style.display = freq ? "block" : "none";
    this.weeklyOptionsTarget.style.display =
      freq === "WEEKLY" ? "block" : "none";
    this.dayFreqErrorTarget.classList.add("d-none");

    this.dayCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = false;
    });
    // Tick the weekday of the start if frequency is WEEKLY
    if (freq === "WEEKLY") {
      const dayIndex = new Date(
        wallOfField(this.startTimeTarget.value),
      ).getUTCDay();
      const box = this.dayCheckboxTargets[dayIndex];
      if (box) box.checked = true;
    }
  }

  warnWithoutWeekday() {
    const none = this.dayCheckboxTargets.every((checkbox) => !checkbox.checked);
    this.dayFreqErrorTarget.classList.toggle("d-none", !none);
  }

  // A click inside the update menu must not close the dropdown.
  keepMenuOpen(event) {
    event.stopPropagation();
  }

  // ---------------------------------------
  // Modal events
  // ---------------------------------------
  confirmExit(event) {
    const confirmed = confirm(this.exitMessageValue);
    if (!confirmed) {
      event.preventDefault();
      event.stopPropagation();
    }
  }

  reset() {
    this.formTarget.reset();
    this.allDayTarget.checked = false;
    this.endTimeTarget.disabled = false;
    this.timeErrorTarget.classList.add("d-none");
    this.saveButtonTarget.disabled = false;
    this.saveButtonTarget.classList.remove("disabled");
    // close the recurrence options
    this.optionsTarget.style.display = "none";
    this.weeklyOptionsTarget.style.display = "none";
    new Collapse(this.collapseTarget, { toggle: false }).hide();
    // hide delete forms
    this.deleteFormsTarget.style.display = "none";
    this.returnFocusTo?.focus();
    this.returnFocusTo = null;
  }

  // Set values on modal open
  proposeTimes() {
    if (!this.startTimeTarget.value) {
      const now = wallOfField("");
      const nextHour = now - (now % HOUR_MS) + HOUR_MS;

      this.startTimeTarget.value = fieldValue(nextHour);
      this.endTimeTarget.value = fieldValue(nextHour + HOUR_MS);
    }

    this.validateTimeRange();
  }

  // Before form submission, send the instants of the Toronto times
  sendInstants() {
    this.buildRule();

    this.utcStartTarget.value = new Date(
      wallToInstant(wallOfField(this.startTimeTarget.value)),
    ).toISOString();
    this.utcEndTarget.value = new Date(
      wallToInstant(wallOfField(this.endTimeTarget.value)),
    ).toISOString();
  }

  // The rule as it is stored: the start in Toronto time, the end a UTC stamp.
  buildRule() {
    const frequency = this.frequencyTarget.value;
    if (frequency === "") {
      this.ruleFieldTarget.value = "";
      return;
    }

    this.ruleFieldTarget.value = storedRule(
      {
        freq: RRule[frequency] || RRule.DAILY,
        byweekday: this.dayCheckboxTargets
          .filter((cb) => cb.checked)
          .map((cb) => RRule[cb.value]),
      },
      wallOfField(this.startTimeTarget.value),
      this.untilTarget.value,
    );
  }
}
