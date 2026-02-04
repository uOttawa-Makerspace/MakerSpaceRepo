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
// Helper to switch input names between "event[name]" and "staff_unavailability[name]"
// -------------------
function setFormScope(scope) {
  const inputs = document.querySelectorAll(
    "#eventModal input, #eventModal select, #eventModal textarea",
  );

  inputs.forEach((input) => {
    // Skip the type select itself, submit buttons, and method spoofers
    if (
      input.id === "event_type_select" ||
      input.name === "_method" ||
      input.type === "submit" ||
      input.type === "button"
    )
      return;

    // Handle the staff select specifically
    if (input.id === "staff_select") {
      if (scope === "staff_unavailability") {
        input.name = "staff_unavailability[user_id]";
        input.removeAttribute("multiple");
      } else {
        input.name = "staff_select[]";
        input.setAttribute("multiple", "multiple");
      }
      return;
    }

    // General regex to swap the scope prefix
    const name = input.name;
    if (name) {
      // Replace event[...] or staff_unavailability[...] with scope[...]
      const newName = name.replace(
        /^(event|staff_unavailability)\[/,
        `${scope}[`,
      );
      input.name = newName;
    }
  });
}

// Helper to toggle between Event Mode and Unavailability Mode
function toggleFormMode(type) {
  const form = document.querySelector("#eventModal form");
  const trainingFields = document.getElementById("training-fields");

  // Reset visibility
  trainingFields.style.display = "none";

  if (type === "unavailability") {
    // UNAVAILABILITY MODE

    // Change Form Action (for Create) - Edit action is handled in eventClick
    if (
      !form.action.includes("/edit") &&
      !form.querySelector('input[name="_method"]')
    ) {
      form.action = "/staff/unavailabilities";
    }

    // Change Input Scoping
    setFormScope("staff_unavailability");
  } else {
    // EVENT MODE (Shift, Meeting, etc)

    // Change Form Action (for Create)
    if (
      !form.action.includes("/edit") &&
      !form.querySelector('input[name="_method"]')
    ) {
      form.action = "/admin/events";
    }

    // Change Input Scoping
    setFormScope("event");

    // Specific Logic
    if (type === "training") {
      trainingFields.style.display = "block";
    }
  }
}

// -------------------
// Full Calendar Event Helpers
// -------------------
export function addEventClick() {
  const form = document.querySelector("#eventModal form");
  form.action = "/admin/events";

  // Reset Scope to default :event
  setFormScope("event");

  const existingMethodInput = form.querySelector('input[name="_method"]');
  if (existingMethodInput) existingMethodInput.remove();

  document.getElementById("eventModalLabel").textContent = "Add Event";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Save Draft";

  const mainFooter = document.getElementById("modal_buttons");
  if (!mainFooter.contains(saveButton)) {
    mainFooter.appendChild(saveButton);
  }

  document.getElementById("update_dropdown").style.display = "none";
  document.getElementById("publish_and_delete_forms").style.display = "none";

  const staffSelect = document.getElementById("staff_select");

  // Ensure it is multiple (Events default)
  staffSelect.setAttribute("multiple", "multiple");

  // Clear any lingering value property
  staffSelect.value = null;

  // Loop through all options and explicitly uncheck them
  // This fixes the issue where the first option stays selected
  Array.from(staffSelect.options).forEach((option) => {
    option.selected = false;
  });

  // Re-attach listener for Event Type change
  const eventTypeSelect = document.getElementById("event_type_select");

  const newSelect = eventTypeSelect.cloneNode(true);
  eventTypeSelect.parentNode.replaceChild(newSelect, eventTypeSelect);

  newSelect.addEventListener("change", (e) => {
    toggleFormMode(e.target.value);
  });

  // Trigger default state
  toggleFormMode(newSelect.value || "shift");
}

export function eventClick(eventImpl) {
  const event = eventImpl._def;
  const id = eventImpl.id.replace("event-", "");
  const isUnavailability = event.extendedProps.eventType === "unavailability";

  // Only edit events (ex. shifts, trainings, meetings, other, unavailability)
  if (!event.extendedProps.eventType) return;

  const form = document.querySelector("#eventModal form");

  // 1. SETUP FORM ACTION & SCOPE
  if (isUnavailability) {
    form.action = `/staff/unavailabilities/${eventImpl.id}`;
    setFormScope("staff_unavailability");
  } else {
    form.action = `/admin/events/${id}`;
    setFormScope("event");
  }

  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "patch";

  // Remove existing method input if any
  const oldMethod = form.querySelector('input[name="_method"]');
  if (oldMethod) oldMethod.remove();
  form.appendChild(methodInput);

  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");
  const allDayCheckbox = document.getElementById("all_day_checkbox");

  if (eventImpl.allDay) {
    allDayCheckbox.checked = true;

    const startDate = new Date(eventImpl.startStr);
    if (eventImpl.startStr.indexOf("T") === -1) {
      startDate.setHours(0, 0, 0, 0);
    }

    const endDate = eventImpl.end
      ? new Date(eventImpl.endStr)
      : new Date(startDate);
    if (!eventImpl.end) endDate.setDate(endDate.getDate() + 1);

    startTimeField.value = toLocalDatetimeString(startDate);
    endTimeField.value = toLocalDatetimeString(endDate);
    endTimeField.disabled = true;
  } else {
    allDayCheckbox.checked = false;
    const start = new Date(eventImpl.startStr);
    startTimeField.value = toLocalDatetimeString(start);
    const end = eventImpl.end
      ? new Date(eventImpl.endStr)
      : new Date(start.getTime() + 3600000);
    endTimeField.value = toLocalDatetimeString(end);
    endTimeField.disabled = false;
  }

  document.getElementById("title").value =
    event.title.replace(/✎/g, "").trim() || "";
  document.getElementById("description").value =
    event.extendedProps.description || "";

  // 4. RECURRENCE
  // unbuild the rrule
  let rruleData = null;

  if (event.recurringDef?.typeData?.rruleSet) {
    rruleData = event.recurringDef.typeData.rruleSet._rrule[0].origOptions;
  } else if (event.extendedProps.rrule) {
    try {
      const rruleStr = event.extendedProps.rrule;
      rruleData = RRule.fromString(
        rruleStr.startsWith("RRULE:") ? rruleStr : `RRULE:${rruleStr}`,
      ).options;
    } catch (e) {
      console.log("RRule parse error", e);
    }
  }

  const frequency = document.querySelector("#recurrence_frequency");
  const options = document.querySelector("#recurrence_options");
  const weeklyOptions = document.querySelector("#weekly_options");
  const untilInput = document.querySelector("#recurrence_until");
  const ruleField = document.querySelector("#recurrence_rule_field");
  const dayCheckboxes = [...document.querySelectorAll(".dayCheckbox")];

  // Reset recurrence
  frequency.value = "";
  options.style.display = "none";
  weeklyOptions.style.display = "none";
  ruleField.value = "";
  untilInput.value = "";
  dayCheckboxes.forEach((cb) => (cb.checked = false));

  if (rruleData) {
    const rule = new RRule(rruleData);
    options.style.display = "block";

    switch (rule.options.freq) {
      case RRule.DAILY:
        frequency.value = "DAILY";
        break;
      case RRule.WEEKLY:
        frequency.value = "WEEKLY";
        weeklyOptions.style.display = "block";

        rule.options.byweekday.forEach((day) => {
          // Simple mapping for standard RRule integers to SU/MO/etc
          const dayMap = {
            0: "MO",
            1: "TU",
            2: "WE",
            3: "TH",
            4: "FR",
            5: "SA",
            6: "SU",
          };
          const dayCode = dayMap[day];
          const cb = document.getElementById(`day_${dayCode}`);
          if (cb) cb.checked = true;
        });
        break;
      case RRule.MONTHLY:
        frequency.value = "MONTHLY";
        break;
    }

    if (rule.options.until)
      untilInput.value = toLocalDateString(rule.options.until);
    ruleField.value = rule.toString();
  }

  // EVENT TYPE & TRAININGS
  const eventTypeSelect = document.getElementById("event_type_select");
  eventTypeSelect.value = event.extendedProps.eventType || "other";

  // Re-attach listener
  const newSelect = eventTypeSelect.cloneNode(true);
  eventTypeSelect.parentNode.replaceChild(newSelect, eventTypeSelect);
  newSelect.addEventListener("change", (e) => {
    toggleFormMode(e.target.value);
  });

  toggleFormMode(eventTypeSelect.value);

  if (eventTypeSelect.value === "training") {
    document.getElementById("training_select").value =
      event.extendedProps.trainingId || null;
    document.getElementById("language_select").value =
      event.extendedProps.language || null;
    document.getElementById("course_select").value =
      event.extendedProps.course_name?.id || null;
  }

  // STAFF SELECTION
  const staffSelect = document.getElementById("staff_select");
  staffSelect.innerHTML = "";

  const assignedUsers = isUnavailability
    ? [
        {
          id: event.extendedProps.userId,
          name: event.extendedProps.name?.split("(")[0] || "User",
        },
      ]
    : event.extendedProps.assignedUsers || [];

  assignedUsers.forEach((staff) => {
    const option = document.createElement("option");
    option.value = staff.id;
    option.textContent = staff.name;
    option.selected = true;
    staffSelect.appendChild(option);
  });

  // Handle Single vs Multi select again to be safe
  if (isUnavailability) {
    staffSelect.removeAttribute("multiple");
    staffSelect.name = "staff_unavailability[user_id]";
  } else {
    staffSelect.setAttribute("multiple", "multiple");
    staffSelect.name = "staff_select[]";
  }

  // FOOTER THINGS
  document.getElementById("eventModalLabel").textContent = isUnavailability
    ? "Edit Unavailability"
    : "Edit Event";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Update";

  // Show update type dropdown if recurrency present
  if (event.recurringDef || rruleData) {
    document.getElementById("update_dropdown_items").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "block";
  } else {
    document.getElementById("modal_buttons").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "none";
  }

  // Handle publish button
  const publishForm = document.getElementById("publish_form");
  if (event.extendedProps.draft && !isUnavailability) {
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

  if (event.recurringDef || rruleData) {
    followingForm.style.display = "block";
    allForm.style.display = "block";
  } else {
    followingForm.style.display = "none";
    allForm.style.display = "none";
  }

  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = parseLocalDatetimeString(eventImpl.startStr).toISOString();
  });

  if (isUnavailability) {
    singleForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
    followingForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
    allForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
  } else {
    singleForm.action = `/admin/events/${id}/delete_with_scope`;
    followingForm.action = `/admin/events/${id}/delete_with_scope`;
    allForm.action = `/admin/events/${id}/delete_with_scope`;
  }

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

  // This must be called after the start and end times are set
  document.getElementById("addEventButton").click();
  addEventClick();
}
