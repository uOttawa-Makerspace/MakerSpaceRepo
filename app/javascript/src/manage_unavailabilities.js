import { Collapse } from "bootstrap";
import { RRule } from "rrule";

import {
  endOfDateInstant,
  fieldValue,
  instantToWall,
  startOfDay,
  wallOfField,
  wallToInstant,
} from "./recurrence.js";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

document.addEventListener("turbo:load", () => {
  const container = document.querySelector("#content");

  // Recurrence rule
  const frequency = container.querySelector("#recurrence_frequency");
  const options = container.querySelector("#recurrence_options");
  const weeklyOptions = container.querySelector("#weekly_options");
  const untilInput = container.querySelector("#recurrence_until");
  const ruleField = container.querySelector("#recurrence_rule_field");
  const dayCheckboxes = [...container.querySelectorAll(".dayCheckbox")];

  // Time selection
  const allDayCheckbox = document.getElementById("all_day_checkbox");
  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");

  // Other stuffs
  const timeError = document.getElementById("time_error");
  const dayFreqError = document.getElementById("day_freq_error");
  const saveButton = document.getElementById("save_button");
  const radios = document.querySelectorAll("#update_dropdown_items *");

  // ---------------------------------------
  // Helper functions
  // ---------------------------------------
  // The form fields hold Toronto wall-clock times, like the calendar.
  function validateTimeRange() {
    const startDate = wallOfField(startTimeField.value);
    const endDate = wallOfField(endTimeField.value);

    if (endDate <= startDate) {
      timeError.classList.remove("d-none");
      saveButton.disabled = true;
      saveButton.classList.add("disabled");
      return false;
    } else {
      timeError.classList.add("d-none");
      saveButton.disabled = false;
      saveButton.classList.remove("disabled");
      return true;
    }
  }

  // The rule is written with instants (UTC stamps), as it is stored.
  function buildRule() {
    if (frequency.value === "") return (ruleField.value = "");

    const rule = new RRule({
      freq: RRule[frequency.value] || RRule.DAILY,
      dtstart: new Date(wallToInstant(wallOfField(startTimeField.value))),
      until: untilInput.value
        ? new Date(endOfDateInstant(untilInput.value))
        : null,
      byweekday: dayCheckboxes
        .filter((cb) => cb.checked)
        .map((cb) => RRule[cb.value]),
    });

    ruleField.value = rule.toString();
  }

  function handleDateIfAllDay() {
    const startDate = startOfDay(wallOfField(startTimeField.value));

    startTimeField.value = fieldValue(startDate);
    endTimeField.value = fieldValue(startDate + DAY_MS);
    endTimeField.disabled = true;

    const freq = frequency.value;
    if (freq === "WEEKLY") {
      const dayIndex = new Date(startDate).getUTCDay();
      dayCheckboxes.forEach((checkbox, index) => {
        checkbox.checked = index === dayIndex;
      });
    }
  }

  // ---------------------------------------
  // Event listeners
  // ---------------------------------------
  allDayCheckbox.addEventListener("change", () => {
    if (allDayCheckbox.checked) {
      handleDateIfAllDay();
    } else {
      endTimeField.disabled = false;
      const start = wallToInstant(wallOfField(startTimeField.value));
      endTimeField.value = fieldValue(instantToWall(start + HOUR_MS));
    }
    validateTimeRange();
  });

  // Auto-set end time when start time changes
  startTimeField.addEventListener("change", () => {
    if (allDayCheckbox.checked) {
      handleDateIfAllDay();
    }
    validateTimeRange();
  });

  // Validate when end time changes manually
  endTimeField.addEventListener("change", validateTimeRange);

  // Manage when frequency changes
  frequency.addEventListener("change", () => {
    const freq = frequency.value;
    options.style.display = freq ? "block" : "none";
    weeklyOptions.style.display = freq === "WEEKLY" ? "block" : "none";
    dayFreqError.classList.add("d-none");

    // Reset checkboxes
    dayCheckboxes.forEach((checkbox) => {
      checkbox.checked = false;
    });
    // Set today's checkbox if frequency is WEEKLY
    if (freq === "WEEKLY") {
      const dayIndex = new Date(wallOfField(startTimeField.value)).getUTCDay();
      if (dayCheckboxes[dayIndex]) dayCheckboxes[dayIndex].checked = true;
    }
  });

  // Manage when the until date or checkboxes change
  [untilInput, ...dayCheckboxes].forEach((el) => {
    el.addEventListener("change", () => {
      if (dayCheckboxes.every((checkbox) => !checkbox.checked)) {
        dayFreqError.classList.remove("d-none");
      } else {
        dayFreqError.classList.add("d-none");
      }
    });
  });

  // "Update" radio buttons
  radios.forEach((radio) => {
    radio.addEventListener("click", (e) => {
      e.stopPropagation(); // Stop the dropdown from closing
    });
  });

  // Confirm before modal exit
  const modal = document.getElementById("unavailabilityModal");
  modal.addEventListener("hide.bs.modal", (e) => {
    const confirmExit = confirm(
      "Are you sure you want to exit? All changes will be lost.",
    );
    if (!confirmExit) {
      e.preventDefault();
      e.stopPropagation();
    }
  });
  // Reset the form
  modal.addEventListener("hidden.bs.modal", () => {
    const form = modal.querySelector("#unavailabilityModal form");
    form.reset();
    allDayCheckbox.checked = false;
    endTimeField.disabled = false;
    timeError.classList.add("d-none");
    saveButton.disabled = false;
    saveButton.classList.remove("disabled");
    // close the recurrence options
    options.style.display = "none";
    weeklyOptions.style.display = "none";
    // close accordion
    const accordion = document.querySelector("#accordion .collapse");
    if (accordion) {
      const collapse = new Collapse(accordion, { toggle: false });
      collapse.hide();
    }
    // hide delete forms
    document.getElementById("delete_forms").style.display = "none";
  });
  // Set values on modal open
  modal.addEventListener("show.bs.modal", (e) => {
    if (!startTimeField.value) {
      const now = wallOfField("");
      const nextHour = now - (now % HOUR_MS) + HOUR_MS;

      startTimeField.value = fieldValue(nextHour);
      endTimeField.value = fieldValue(nextHour + HOUR_MS);
    }

    validateTimeRange();
  });

  // Before form submission, send the instants of the Toronto times
  document.getElementById("unavailForm").addEventListener("submit", (e) => {
    buildRule();

    document.getElementById("utc_start_time").value = new Date(
      wallToInstant(wallOfField(startTimeField.value)),
    ).toISOString();
    document.getElementById("utc_end_time").value = new Date(
      wallToInstant(wallOfField(endTimeField.value)),
    ).toISOString();
  });
});
