import { RRule } from "rrule";
import { Modal } from "bootstrap";

/*
 * Converts a Date object to a local datetime string in the format YYYY-MM-DDTHH:MM
 * If the value is empty, it returns null.
 */
export function toLocalDatetimeString(date) {
  if (!date) return null;

  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/*
 * Converts a Date object to a local date string in the format YYYY-MM-DD
 * If the value is empty, it returns null.
 */
export function toLocalDateString(date) {
  if (!date) return null;

  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/*
 * Parses a local datetime string in the format YYYY-MM-DDTHH:MM
 * and returns a Date object.
 * If the value is empty, it returns the current date.
 */
export function parseLocalDatetimeString(value) {
  if (!value) return new Date();
  return new Date(value);
}

// -------------------
// Full Calendar Event Helpers
// -------------------
export function addEventClick() {
  const form = document.querySelector("#eventModal form");
  form.action = "/admin/events";
  const existingMethodInput = form.querySelector('input[name="_method"]');
  if (existingMethodInput) existingMethodInput.remove();

  document.getElementById("eventModalLabel").textContent = "Add Event";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Save Draft";
  document.getElementById("modal_buttons").appendChild(saveButton);
  document.getElementById("update_dropdown").style.display = "none";
  document.getElementById("publish_and_delete_forms").style.display = "none";
}

export function eventClick(eventImpl) {
  const event = eventImpl._def;
  const id = eventImpl.id.replace("event-", "");

  // Only edit events (ex. shifts, trainings, meetings, other)
  if (!event.extendedProps.eventType) return;

  // Set form action to edit path
  const form = document.querySelector("#eventModal form");
  form.action = `/admin/events/${id}`;
  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "patch";
  form.appendChild(methodInput);

  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");

  if (eventImpl.allDay) {
    document.getElementById("all_day_checkbox").checked = true;

    const startDate = new Date(eventImpl.startStr);
    startDate.setHours(0, 0, 0, 0);

    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + 1);

    startTimeField.value = toLocalDatetimeString(startDate);
    endTimeField.value = toLocalDatetimeString(endDate);
    endTimeField.disabled = true;
  } else {
    const start = new Date(eventImpl.startStr);
    startTimeField.value = toLocalDatetimeString(start);
    const end = new Date(eventImpl.endStr);
    endTimeField.value = toLocalDatetimeString(end);
  }

  document.getElementById("title").value =
    event.title.replace(/✎/g, "").trim() || "";
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

    untilInput.value = toLocalDateString(rule.options.until);
    ruleField.value = rule.toString();
  }

  // Set the event type
  const eventTypeSelect = document.getElementById("event_type_select");
  eventTypeSelect.value = event.extendedProps.eventType || "other";

  // Show options if event is a training
  const trainingFields = document.getElementById("training-fields");
  if (eventTypeSelect.value === "training") {
    trainingFields.style.display = "";

    // Populate training options
    document.getElementById("training_select").value =
      event.extendedProps.trainingId || null;
    document.getElementById("language_select").value =
      event.extendedProps.language || null;
    document.getElementById("course_select").value =
      event.extendedProps.course_name.id || null;
  } else {
    trainingFields.style.display = "none";
  }

  // Set the staff members
  const staffSelect = document.getElementById("staff_select");
  const assignedStaff = event.extendedProps.assignedUsers || [];
  // append the current staff members to the select
  assignedStaff.forEach((staff) => {
    const option = document.createElement("option");
    option.value = staff.id;
    option.textContent = staff.name;
    option.selected = true;
    staffSelect.appendChild(option);
  });

  // Footer things
  document.getElementById("eventModalLabel").textContent = "Edit Event";
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

  // Handle publish button
  const publishForm = document.getElementById("publish_form");
  if (event.extendedProps.draft) {
    publishForm.action = `/admin/events/${id}/publish`;
    publishForm.style.display = "block";
  } else {
    publishForm.style.display = "none";
  }

  // Handle delete buttons
  document.getElementById("publish_and_delete_forms").style.display = "flex";

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

  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = parseLocalDatetimeString(eventImpl.startStr).toISOString();
  });

  singleForm.action = `/admin/events/${id}/delete_with_scope`;
  followingForm.action = `/admin/events/${id}/delete_with_scope`;
  allForm.action = `/admin/events/${id}/delete_with_scope`;

  // Show modal FINALLY
  const modal = new Modal(document.getElementById("eventModal"));
  modal.show();
}

export function eventCreate(info) {
  document.getElementById("start_time_field").value = toLocalDatetimeString(
    new Date(info.startStr),
  );
  document.getElementById("end_time_field").value = toLocalDatetimeString(
    new Date(info.endStr),
  );

  document.getElementById("training-fields").style.display = "none";

  // This must be called after the start and end times are set, since marking staff as unavailable (on modal show) relies on these values.
  document.getElementById("addEventButton").click();
  addEventClick();
}
