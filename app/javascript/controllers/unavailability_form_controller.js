import { Controller } from "@hotwired/stimulus";
import { Collapse } from "bootstrap";
import { RRule } from "rrule";

import {
  fieldValue,
  instantToWall,
  startOfDay,
  storedRule,
  wallOfField,
  wallToInstant,
} from "../src/recurrence.js";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

// The unavailability dialog (add and edit): validates the time range, handles
// all-day entries and repeat options, and sends the Toronto wall-clock times as
// instants with the stored recurrence rule when the form is submitted. It only
// reads and writes inside its own element.
export default class extends Controller {
  connect() {
    this.listeners = new AbortController();
    const { signal } = this.listeners;

    this.frequency = this.input("#recurrence_frequency");
    this.options = this.find("#recurrence_options");
    this.weeklyOptions = this.find("#weekly_options");
    this.untilInput = this.input("#recurrence_until");
    this.ruleField = this.input("#recurrence_rule_field");
    this.dayCheckboxes = /** @type {HTMLInputElement[]} */ ([
      ...this.element.querySelectorAll(".dayCheckbox"),
    ]);
    this.allDayCheckbox = this.input("#all_day_checkbox");
    this.startTimeField = this.input("#start_time_field");
    this.endTimeField = this.input("#end_time_field");
    this.timeError = this.find("#time_error");
    this.dayFreqError = this.find("#day_freq_error");
    this.saveButton = this.input("#save_button");

    this.listenToTimes(signal);
    this.listenToRepeat(signal);
    this.listenToModal(signal);
    this.find("#unavailForm").addEventListener(
      "submit",
      () => this.sendInstants(),
      { signal },
    );
  }

  disconnect() {
    this.listeners?.abort();
  }

  /** @returns {HTMLElement} */
  find(selector) {
    return this.element.querySelector(selector);
  }

  /** @returns {HTMLInputElement} */
  input(selector) {
    return this.element.querySelector(selector);
  }

  listenToTimes(signal) {
    this.allDayCheckbox.addEventListener("change", () => this.allDayChanged(), {
      signal,
    });
    // Auto-set end time when start time changes
    this.startTimeField.addEventListener(
      "change",
      () => {
        if (this.allDayCheckbox.checked) this.snapToAllDay();
        this.validateTimeRange();
      },
      { signal },
    );
    // Validate when end time changes manually
    this.endTimeField.addEventListener(
      "change",
      () => this.validateTimeRange(),
      { signal },
    );
  }

  listenToRepeat(signal) {
    this.frequency.addEventListener("change", () => this.frequencyChanged(), {
      signal,
    });
    [this.untilInput, ...this.dayCheckboxes].forEach((el) => {
      el.addEventListener("change", () => this.warnWithoutWeekday(), {
        signal,
      });
    });
    // "Update" radio buttons: keep a click from closing the dropdown
    this.element
      .querySelectorAll("#update_dropdown_items *")
      .forEach((radio) => {
        radio.addEventListener("click", (e) => e.stopPropagation(), {
          signal,
        });
      });
  }

  listenToModal(signal) {
    // Confirm before modal exit
    this.element.addEventListener("hide.bs.modal", (e) => this.confirmExit(e), {
      signal,
    });
    this.element.addEventListener("hidden.bs.modal", () => this.reset(), {
      signal,
    });
    this.element.addEventListener("show.bs.modal", () => this.proposeTimes(), {
      signal,
    });
  }

  // The form fields hold Toronto wall-clock times, like the calendar.
  validateTimeRange() {
    const startDate = wallOfField(this.startTimeField.value);
    const endDate = wallOfField(this.endTimeField.value);
    const valid = endDate > startDate;

    this.timeError.classList.toggle("d-none", valid);
    this.saveButton.disabled = !valid;
    this.saveButton.classList.toggle("disabled", !valid);
    return valid;
  }

  // The rule as it is stored: the start in Toronto time, the end a UTC stamp.
  buildRule() {
    if (this.frequency.value === "") {
      this.ruleField.value = "";
      return;
    }

    this.ruleField.value = storedRule(
      {
        freq: RRule[this.frequency.value] || RRule.DAILY,
        byweekday: this.dayCheckboxes
          .filter((cb) => cb.checked)
          .map((cb) => RRule[cb.value]),
      },
      wallOfField(this.startTimeField.value),
      this.untilInput.value,
    );
  }

  snapToAllDay() {
    const startDate = startOfDay(wallOfField(this.startTimeField.value));

    this.startTimeField.value = fieldValue(startDate);
    this.endTimeField.value = fieldValue(startDate + DAY_MS);
    this.endTimeField.disabled = true;

    if (this.frequency.value === "WEEKLY") {
      const dayIndex = new Date(startDate).getUTCDay();
      this.dayCheckboxes.forEach((checkbox, index) => {
        checkbox.checked = index === dayIndex;
      });
    }
  }

  allDayChanged() {
    if (this.allDayCheckbox.checked) {
      this.snapToAllDay();
    } else {
      this.endTimeField.disabled = false;
      const start = wallToInstant(wallOfField(this.startTimeField.value));
      this.endTimeField.value = fieldValue(instantToWall(start + HOUR_MS));
    }
    this.validateTimeRange();
  }

  // Manage when frequency changes
  frequencyChanged() {
    const freq = this.frequency.value;
    this.options.style.display = freq ? "block" : "none";
    this.weeklyOptions.style.display = freq === "WEEKLY" ? "block" : "none";
    this.dayFreqError.classList.add("d-none");

    this.dayCheckboxes.forEach((checkbox) => {
      checkbox.checked = false;
    });
    // Set the weekday of the start if frequency is WEEKLY
    if (freq === "WEEKLY") {
      const dayIndex = new Date(
        wallOfField(this.startTimeField.value),
      ).getUTCDay();
      if (this.dayCheckboxes[dayIndex])
        this.dayCheckboxes[dayIndex].checked = true;
    }
  }

  warnWithoutWeekday() {
    const none = this.dayCheckboxes.every((checkbox) => !checkbox.checked);
    this.dayFreqError.classList.toggle("d-none", !none);
  }

  confirmExit(event) {
    const confirmExit = confirm(
      "Are you sure you want to exit? All changes will be lost.",
    );
    if (!confirmExit) {
      event.preventDefault();
      event.stopPropagation();
    }
  }

  reset() {
    /** @type {HTMLFormElement} */ (this.find("form")).reset();
    this.allDayCheckbox.checked = false;
    this.endTimeField.disabled = false;
    this.timeError.classList.add("d-none");
    this.saveButton.disabled = false;
    this.saveButton.classList.remove("disabled");
    // close the recurrence options
    this.options.style.display = "none";
    this.weeklyOptions.style.display = "none";
    // close accordion
    const accordion = this.find("#accordion .collapse");
    if (accordion) {
      new Collapse(accordion, { toggle: false }).hide();
    }
    // hide delete forms
    this.find("#delete_forms").style.display = "none";
  }

  // Set values on modal open
  proposeTimes() {
    if (!this.startTimeField.value) {
      const now = wallOfField("");
      const nextHour = now - (now % HOUR_MS) + HOUR_MS;

      this.startTimeField.value = fieldValue(nextHour);
      this.endTimeField.value = fieldValue(nextHour + HOUR_MS);
    }

    this.validateTimeRange();
  }

  // Before form submission, send the instants of the Toronto times
  sendInstants() {
    this.buildRule();

    this.input("#utc_start_time").value = new Date(
      wallToInstant(wallOfField(this.startTimeField.value)),
    ).toISOString();
    this.input("#utc_end_time").value = new Date(
      wallToInstant(wallOfField(this.endTimeField.value)),
    ).toISOString();
  }
}
