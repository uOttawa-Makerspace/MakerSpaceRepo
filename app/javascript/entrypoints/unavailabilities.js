import { Modal } from "bootstrap";
import { RRule, rrulestr } from "rrule";

import {
  parseLocalDatetimeString,
  toLocalDateString,
  toLocalDatetimeString,
} from "./calendar_helper";

document.addEventListener("turbo:load", () => {
  document
    .getElementById("addUnavailabilityButton")
    .addEventListener("click", addUnavailabilityClick);
});

export function eventClick(info, events) {
  const event = info.event;
  const eventFromEvents = events.find((e) => e.id == event.id);

  // Show modal
  const modal = new Modal(document.getElementById("unavailabilityModal"));
  modal.show();

  // Set form action to edit path
  const form = document.querySelector("#unavailabilityModal form");
  form.action = `/staff/unavailabilities/${event.id}`;
  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "patch";
  form.appendChild(methodInput);

  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");

  if (event.allDay) {
    document.getElementById("all_day_checkbox").checked = true;

    const startDate = new Date(event.start);
    startDate.setHours(0, 0, 0, 0);

    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + 1);

    startTimeField.value = toLocalDatetimeString(startDate);
    endTimeField.value = toLocalDatetimeString(endDate);
    endTimeField.disabled = true;
  } else {
    const start = new Date(event.start);
    startTimeField.value = toLocalDatetimeString(start);
    const duration =
      new Date(eventFromEvents.end) - new Date(eventFromEvents.start);
    endTimeField.value = toLocalDatetimeString(
      new Date(start.getTime() + duration),
    );
  }

  document.getElementById("title").value = event.title || "";
  document.getElementById("description").value =
    event.extendedProps.description || "";

  // unbuild the rrule
  if (eventFromEvents.rrule) {
    const rule = rrulestr(eventFromEvents.rrule);

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

    untilInput.value = toLocalDateString(rule.options.until);
    ruleField.value = eventFromEvents.rrule;
  }

  document.getElementById("unavailabilityModalLabel").textContent =
    "Edit Unavailability";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Update";

  // Show update type dropdown if recurrency present
  if (eventFromEvents.rrule) {
    document.getElementById("update_dropdown_items").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "block";
  } else {
    document.getElementById("modal_buttons").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "none";
  }

  // Handle delete buttons
  document.getElementById("delete_forms").style.display = "block";

  const singleForm = document.getElementById("delete_single_form");
  const followingForm = document.getElementById("delete_following_form");
  const allForm = document.getElementById("delete_all_form");

  if (eventFromEvents.rrule) {
    followingForm.style.display = "block";
    allForm.style.display = "block";
  } else {
    followingForm.style.display = "none";
    allForm.style.display = "none";
  }

  const id = event.id;

  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = parseLocalDatetimeString(event.start).toISOString();
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

  document.getElementById("start_time_field").value = toLocalDatetimeString(
    info.start,
  );
  document.getElementById("end_time_field").value = toLocalDatetimeString(
    info.end,
  );
}
