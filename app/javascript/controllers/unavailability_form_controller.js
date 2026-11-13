import { Controller } from "@hotwired/stimulus";
import { Collapse, Modal } from "bootstrap";
import { RRule } from "rrule";

import {
  fieldValue,
  instantToWall,
  startOfDay,
  storedRule,
  wallEnd,
  wallFromCalendar,
  wallOfField,
  wallToInstant,
} from "../src/recurrence.js";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const COLLECTION_PATH = "/staff/unavailabilities";

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
  methodFieldTarget: HTMLInputElement,
  deleteChoicesTarget: HTMLElement,
  deleteFormTargets: HTMLFormElement[],
  deleteStartDateTargets: HTMLInputElement[],
  keepTimesTarget: HTMLInputElement,
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
    "methodField",
    "deleteChoices",
    "deleteForm",
    "deleteStartDate",
    "keepTimes",
  ];

  // ---------------------------------------
  // Opening the dialog
  // ---------------------------------------
  // The element given as returnFocusTo gets the focus back when the dialog
  // closes (the button that opened it).
  openForAdd({ returnFocusTo = null } = {}) {
    this.returnFocusTo = returnFocusTo;
    this.filledTimes = null;
    this.formTarget.action = COLLECTION_PATH;
    this.methodFieldTarget.disabled = true;

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

  // The entry is a plain object (see editableUnavailability): its record id,
  // title, description, all-day flag, the calendar's start and end strings,
  // the occurrence's start instant and, for a repeating entry, what the feed
  // sent of its repeat.
  openForEdit(entry) {
    const repeats = Boolean(entry.series);

    this.modal.show();
    this.pointFormAt(entry.id);
    this.fillTimes(entry);
    this.filledTimes = this.timesShown();
    this.titleFieldTarget.value = entry.title || "";
    this.descriptionFieldTarget.value = entry.description || "";
    if (repeats) this.restoreSeries(entry.series);

    this.labelTarget.textContent = "Edit Unavailability";
    this.saveButtonTarget.value = "Update";
    this.placeSaveButton(repeats);
    this.showDeleteChoices(entry, repeats);
  }

  get modal() {
    return Modal.getOrCreateInstance(this.element);
  }

  pointFormAt(id) {
    this.formTarget.action = `${COLLECTION_PATH}/${encodeURIComponent(id)}`;
    this.methodFieldTarget.disabled = false;
  }

  // The fields hold Toronto wall-clock times, like the calendar. An occurrence
  // whose wall-clock end is its start (one hour from the first 1:30 of the
  // night the clocks go back) has no end in the calendar; the form ends it one
  // wall-clock hour after its start.
  fillTimes(entry) {
    if (entry.allDay) {
      this.allDayTarget.checked = true;
      const startDate = startOfDay(wallFromCalendar(entry.startStr));
      this.startTimeTarget.value = fieldValue(startDate);
      this.endTimeTarget.value = fieldValue(startDate + DAY_MS);
      this.endTimeTarget.disabled = true;
    } else {
      const start = wallFromCalendar(entry.startStr);
      this.startTimeTarget.value = fieldValue(start);
      this.endTimeTarget.value = fieldValue(wallEnd(entry.endStr, start));
    }
  }

  // The repeat fields of a series as the feed sent it: its frequency, its
  // weekdays and the day it repeats until (the rule is built again on submit).
  restoreSeries({ frequency, weekdays, until }) {
    const weekly = frequency === "WEEKLY";
    this.optionsTarget.style.display = "block";
    this.weeklyOptionsTarget.style.display = weekly ? "block" : "none";
    this.frequencyTarget.value = frequency;
    this.dayCheckboxTargets.forEach((box) => {
      box.checked = weekly && weekdays.includes(box.value);
    });
    this.untilTarget.value = until || "";
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

  showDeleteChoices(entry, repeats) {
    const id = encodeURIComponent(entry.id);
    const path = `${COLLECTION_PATH}/${id}/delete_with_scope`;
    this.deleteFormTargets.forEach((form) => {
      form.action = path;
      // Only a repeating entry can be deleted from here on or as a series
      if (form.dataset.repeatingOnly) {
        form.style.display = repeats ? "block" : "none";
      }
    });
    this.deleteChoicesTarget.style.display = "flex";

    // The instant of the clicked occurrence, as the server sent it
    this.deleteStartDateTargets.forEach((input) => {
      input.value = entry.occurrenceStart;
    });
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
    this.deleteChoicesTarget.style.display = "none";
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
    // "update all" keeps the series' own times unless they were changed here:
    // the field ("1") is sent only while the times are as they were filled
    this.keepTimesTarget.disabled = this.timesShown() !== this.filledTimes;

    this.utcStartTarget.value = new Date(
      wallToInstant(wallOfField(this.startTimeTarget.value)),
    ).toISOString();
    this.utcEndTarget.value = new Date(
      wallToInstant(wallOfField(this.endTimeTarget.value)),
    ).toISOString();
  }

  // The time fields as they stand.
  timesShown() {
    return [
      this.startTimeTarget.value,
      this.endTimeTarget.value,
      this.allDayTarget.checked,
    ].join("|");
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
