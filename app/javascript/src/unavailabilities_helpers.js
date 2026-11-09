import { Modal } from "bootstrap";
import { RRule } from "rrule";

import {
  dateValue,
  fieldValue,
  instantFromCalendar,
  startOfDay,
  storedRule,
  wallFromCalendar,
} from "./recurrence";

const DAY_MS = 24 * 60 * 60 * 1000;

// This function closely matches ./calendar.js eventClick
export function eventClick(eventImpl) {
  const event = eventImpl._def;
  const id = eventImpl.id;

  // Show modal
  const modal = new Modal(document.getElementById("unavailabilityModal"));
  modal.show();

  // Set form action to edit path
  const form = document.querySelector("#unavailabilityModal form");
  form.action = `/staff/unavailabilities/${id}`;
  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "patch";
  form.appendChild(methodInput);

  // The fields hold Toronto wall-clock times, like the calendar.
  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");

  if (eventImpl.allDay) {
    document.getElementById("all_day_checkbox").checked = true;

    const startDate = startOfDay(wallFromCalendar(eventImpl.startStr));
    startTimeField.value = fieldValue(startDate);
    endTimeField.value = fieldValue(startDate + DAY_MS);
    endTimeField.disabled = true;
  } else {
    startTimeField.value = fieldValue(wallFromCalendar(eventImpl.startStr));
    endTimeField.value = fieldValue(wallFromCalendar(eventImpl.endStr));
  }

  document.getElementById("title").value = event.title || "";
  document.getElementById("description").value =
    event.extendedProps.description || "";

  // unbuild the rrule
  if (
    event.recurringDef &&
    event.recurringDef.typeData &&
    event.recurringDef.typeData.rruleSet
  ) {
    const rule = new RRule(
      event.recurringDef.typeData.rruleSet._rrule[0].origOptions,
    );

    const frequency = document.querySelector("#recurrence_frequency");
    const options = document.querySelector("#recurrence_options");
    const weeklyOptions = document.querySelector("#weekly_options");
    const untilInput = document.querySelector("#recurrence_until");
    const ruleField = document.querySelector("#recurrence_rule_field");
    const dayCheckboxes = [...document.querySelectorAll(".dayCheckbox")];

    options.style.display = "block";
    weeklyOptions.style.display = "none";

    switch (rule.options.freq) {
      case RRule.DAILY:
        frequency.value = "DAILY";
        break;
      case RRule.WEEKLY:
        frequency.value = "WEEKLY";
        weeklyOptions.style.display = "block";

        rule.options.byweekday.forEach((day) => {
          // rrule has MO=0 while we use SU=0...
          if (dayCheckboxes[day + 1]) {
            dayCheckboxes[day + 1].checked = true;
          } else {
            dayCheckboxes[0].checked = true;
          }
        });
        break;
      case RRule.MONTHLY:
        frequency.value = "MONTHLY";
        break;
    }

    untilInput.value = rule.options.until
      ? dateValue(rule.options.until.getTime())
      : null;
    // The feed's start is a Toronto wall time already
    ruleField.value = storedRule(
      { freq: rule.options.freq, byweekday: rule.options.byweekday },
      rule.options.dtstart.getTime(),
      untilInput.value,
    );
  }

  document.getElementById("unavailabilityModalLabel").textContent =
    "Edit Unavailability";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Update";

  // Show update type dropdown if recurrency present
  if (event.recurringDef) {
    document.getElementById("update_dropdown_items").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "block";
  } else {
    document.getElementById("modal_buttons").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "none";
  }

  // Handle delete buttons
  document.getElementById("delete_forms").style.display = "flex";

  const singleForm = document.getElementById("delete_single_form");
  const followingForm = document.getElementById("delete_following_form");
  const allForm = document.getElementById("delete_all_form");

  if (event.recurringDef) {
    followingForm.style.display = "block";
    allForm.style.display = "block";
  } else {
    followingForm.style.display = "none";
    allForm.style.display = "none";
  }

  // The instant of the clicked occurrence
  const occurrenceStart = new Date(
    instantFromCalendar(eventImpl.startStr),
  ).toISOString();
  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = occurrenceStart;
  });

  singleForm.action = `/staff/unavailabilities/${id}/delete_with_scope`;
  followingForm.action = `/staff/unavailabilities/${id}/delete_with_scope`;
  allForm.action = `/staff/unavailabilities/${id}/delete_with_scope`;
}

export function addUnavailabilityClick() {
  const form = document.querySelector("#unavailabilityModal form");
  form.action = "/staff/unavailabilities";
  const existingMethodInput = form.querySelector('input[name="_method"]');
  if (existingMethodInput) existingMethodInput.remove();

  document.getElementById("unavailabilityModalLabel").textContent =
    "Add Unavailability";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Save";
  document.getElementById("modal_buttons").appendChild(saveButton);
  document.getElementById("update_dropdown").style.display = "none";
}

export function eventCreate(info) {
  document.getElementById("addUnavailabilityButton").click();
  addUnavailabilityClick();

  document.getElementById("start_time_field").value = fieldValue(
    wallFromCalendar(info.startStr),
  );
  document.getElementById("end_time_field").value = fieldValue(
    wallFromCalendar(info.endStr),
  );
}
