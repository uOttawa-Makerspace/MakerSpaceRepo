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
// Reset modal to clean state
// -------------------
function resetModalState() {
  const form = document.querySelector("#eventModal form");
  const saveButton = document.getElementById("save_button");
  const saveButtonContainer = document.getElementById("save_button_container");
  const dropdownSaveContainer = document.getElementById(
    "dropdown_save_button_container",
  );
  const updateDropdown = document.getElementById("update_dropdown");
  const eventTypeSelect = document.getElementById("event_type_select");
  const staffSelect = document.getElementById("staff_select");

  // Move save button back to main container
  if (
    saveButton &&
    saveButtonContainer &&
    !saveButtonContainer.contains(saveButton)
  ) {
    saveButtonContainer.appendChild(saveButton);
  }

  // Hide the update dropdown
  if (updateDropdown) {
    updateDropdown.style.display = "none";
  }

  // Reset save button text
  if (saveButton) {
    saveButton.value = "Save Draft";
  }

  // Remove any _method input (used for PATCH/DELETE)
  const methodInput = form?.querySelector('input[name="_method"]');
  if (methodInput) methodInput.remove();

  // Reset form action
  if (form) {
    form.action = "/admin/events";
  }

  // Reset event type select
  if (eventTypeSelect) {
    eventTypeSelect.disabled = false;
    eventTypeSelect.value = "";

    // Remove lock indicator if present
    const lockIndicator =
      eventTypeSelect.parentElement?.querySelector(".lock-indicator");
    if (lockIndicator) lockIndicator.remove();

    // Remove hidden type input
    const hiddenTypeInput = form?.querySelector(
      'input[name="staff_unavailability[event_type]"]',
    );
    if (hiddenTypeInput) hiddenTypeInput.remove();
  }

  // Reset staff select
  if (staffSelect) {
    staffSelect.innerHTML = "";
    staffSelect.setAttribute("multiple", "multiple");
    staffSelect.name = "staff_select[]";
  }

  // Reset recurrence fields
  const frequency = document.querySelector("#recurrence_frequency");
  const options = document.querySelector("#recurrence_options");
  const weeklyOptions = document.querySelector("#weekly_options");
  const untilInput = document.querySelector("#recurrence_until");
  const ruleField = document.querySelector("#recurrence_rule_field");
  const dayCheckboxes = [...document.querySelectorAll(".dayCheckbox")];

  if (frequency) frequency.value = "";
  if (options) options.style.display = "none";
  if (weeklyOptions) weeklyOptions.style.display = "none";
  if (ruleField) ruleField.value = "";
  if (untilInput) untilInput.value = "";
  dayCheckboxes.forEach((cb) => (cb.checked = false));

  // Reset other form fields
  const titleField = document.getElementById("title");
  const descField = document.getElementById("description");
  const allDayCheckbox = document.getElementById("all_day_checkbox");
  const endTimeField = document.getElementById("end_time_field");
  const trainingFields = document.getElementById("training-fields");

  if (titleField) titleField.value = "";
  if (descField) descField.value = "";
  if (allDayCheckbox) allDayCheckbox.checked = false;
  if (endTimeField) endTimeField.disabled = false;
  if (trainingFields) trainingFields.style.display = "none";

  // Reset update scope radio buttons
  const updateThis = document.getElementById("update_this");
  if (updateThis) updateThis.checked = true;

  // Hide publish/delete footer
  document.getElementById("publish_and_delete_forms").style.display = "none";
  document.getElementById("publish_form").style.display = "none";
  document.getElementById("delete_following_form").style.display = "none";
  document.getElementById("delete_all_form").style.display = "none";

  // Reset modal title
  document.getElementById("eventModalLabel").textContent = "Add Event";

  // Reset form scope to event
  setFormScope("event");
}

// -------------------
// Helper to switch input names between "event[name]" and "staff_unavailability[name]"
// -------------------
function setFormScope(scope) {
  const form = document.querySelector("#eventModal form");
  if (!form) return;

  // Define field mappings
  const fieldMappings = {
    start_time_field: "utc_start_time",
    end_time_field: "utc_end_time",
    recurrence_rule_field: "recurrence_rule",
    title: "title",
    description: "description",
    utc_start_time: "utc_start_time",
    utc_end_time: "utc_end_time",
  };

  // Update specific fields
  Object.entries(fieldMappings).forEach(([fieldId, paramName]) => {
    const field = document.getElementById(fieldId);
    if (field) {
      field.name = `${scope}[${paramName}]`;
    }
  });

  // Handle staff select specifically
  const staffSelect = document.getElementById("staff_select");
  if (staffSelect) {
    if (scope === "staff_unavailability") {
      staffSelect.name = "staff_unavailability[user_id]";
      staffSelect.removeAttribute("multiple");
    } else {
      staffSelect.name = "staff_select[]";
      staffSelect.setAttribute("multiple", "multiple");
    }
  }

  // Handle space_id
  const spaceIdField = form.querySelector(
    'input[id$="space_id"], input[name$="[space_id]"]',
  );
  if (spaceIdField) {
    spaceIdField.name = `${scope}[space_id]`;
  }
}

// -------------------
// Helper to toggle between Event Mode and Unavailability Mode
// -------------------
function toggleFormMode(type) {
  const form = document.querySelector("#eventModal form");
  const trainingFields = document.getElementById("training-fields");

  // Reset visibility
  if (trainingFields) trainingFields.style.display = "none";

  if (type === "unavailability") {
    // UNAVAILABILITY MODE
    const methodInput = form?.querySelector('input[name="_method"]');
    if (!form.action.includes("/unavailabilities") && !methodInput) {
      form.action = "/staff/unavailabilities";
    }

    // Change Input Scoping
    setFormScope("staff_unavailability");
  } else {
    // EVENT MODE
    const methodInput = form?.querySelector('input[name="_method"]');
    if (!form.action.includes("/events/") && !methodInput) {
      form.action = "/admin/events";
    }

    // Change Input Scoping
    setFormScope("event");

    if (type === "training" && trainingFields) {
      trainingFields.style.display = "block";
    }
  }
}

// -------------------
// Helper to lock/unlock event type dropdown
// -------------------
function setEventTypeLock(isLocked) {
  const form = document.querySelector("#eventModal form");
  const eventTypeSelect = document.getElementById("event_type_select");
  if (!eventTypeSelect) return;

  const eventTypeContainer =
    eventTypeSelect.closest(".mb-3") || eventTypeSelect.parentElement;

  if (isLocked) {
    eventTypeSelect.disabled = true;

    // Add hidden input for form submission
    let hiddenTypeInput = form?.querySelector(
      'input[name="staff_unavailability[event_type]"]',
    );
    if (!hiddenTypeInput && form) {
      hiddenTypeInput = document.createElement("input");
      hiddenTypeInput.type = "hidden";
      hiddenTypeInput.name = "staff_unavailability[event_type]";
      hiddenTypeInput.id = "event_type_hidden";
      hiddenTypeInput.value = "unavailability";
      form.appendChild(hiddenTypeInput);
    }

    // Add visual indicator
    let lockIndicator = eventTypeContainer?.querySelector(".lock-indicator");
    if (!lockIndicator && eventTypeContainer) {
      lockIndicator = document.createElement("small");
      lockIndicator.className = "lock-indicator text-muted d-block mt-1";
      lockIndicator.textContent = "🔒 Unavailability type cannot be changed";
      eventTypeContainer.appendChild(lockIndicator);
    }
  } else {
    eventTypeSelect.disabled = false;

    // Remove hidden type input
    const hiddenTypeInput = form?.querySelector(
      'input[name="staff_unavailability[event_type]"]',
    );
    if (hiddenTypeInput) hiddenTypeInput.remove();

    // Remove lock indicator
    const lockIndicator = eventTypeContainer?.querySelector(".lock-indicator");
    if (lockIndicator) lockIndicator.remove();
  }
}

// -------------------
// Position save button correctly based on recurrence
// -------------------
function positionSaveButton(hasRecurrence, isEditing) {
  const saveButton = document.getElementById("save_button");
  const saveButtonContainer = document.getElementById("save_button_container");
  const dropdownSaveContainer = document.getElementById(
    "dropdown_save_button_container",
  );
  const updateDropdown = document.getElementById("update_dropdown");

  if (!saveButton) return;

  if (hasRecurrence && isEditing) {
    // Move to dropdown for recurring event edits
    if (dropdownSaveContainer && !dropdownSaveContainer.contains(saveButton)) {
      dropdownSaveContainer.appendChild(saveButton);
    }
    if (updateDropdown) updateDropdown.style.display = "block";
    saveButton.value = "Update";
  } else {
    // Keep in main container
    if (saveButtonContainer && !saveButtonContainer.contains(saveButton)) {
      saveButtonContainer.appendChild(saveButton);
    }
    if (updateDropdown) updateDropdown.style.display = "none";
    saveButton.value = isEditing ? "Update" : "Save Draft";
  }
}

// -------------------
// Populate staff users for the select
// -------------------
async function populateStaffSelect() {
  const staffSelect = document.getElementById("staff_select");
  if (!staffSelect) return;

  // Only populate if empty
  if (staffSelect.options.length > 0) return;

  try {
    const spaceIdElem =
      document.getElementById("space_id") ||
      document.querySelector('input[name="event[space_id]"]') ||
      document.querySelector('input[name="staff_unavailability[space_id]"]');

    if (!spaceIdElem) return;

    const response = await fetch(
      `/admin/calendar/staff_json/${spaceIdElem.value}`,
    );
    if (!response.ok) return;

    const staffData = await response.json();

    staffData.forEach((staff) => {
      const option = document.createElement("option");
      option.value = staff.id;
      option.textContent = staff.name;
      staffSelect.appendChild(option);
    });
  } catch (error) {
    console.error("Error fetching staff data:", error);
  }
}

// -------------------
// Full Calendar Event Helpers
// -------------------
export function addEventClick() {
  // Reset everything first
  resetModalState();

  // Populate staff options if needed
  populateStaffSelect();

  // Set up event type change listener
  const eventTypeSelect = document.getElementById("event_type_select");
  if (eventTypeSelect) {
    // Clone to remove old listeners
    const newSelect = eventTypeSelect.cloneNode(true);
    eventTypeSelect.parentNode.replaceChild(newSelect, eventTypeSelect);

    newSelect.addEventListener("change", (e) => {
      toggleFormMode(e.target.value);
    });
  }

  // Default state
  toggleFormMode("shift");
}

export function eventClick(eventImpl) {
  const event = eventImpl._def;
  const id = eventImpl.id.replace("event-", "");
  const isUnavailability = event.extendedProps.eventType === "unavailability";

  // Only edit events with an eventType
  if (!event.extendedProps.eventType) return;

  // Reset modal first
  resetModalState();

  const form = document.querySelector("#eventModal form");

  // SETUP FORM ACTION & METHOD
  if (isUnavailability) {
    form.action = `/staff/unavailabilities/${eventImpl.id}`;
    setFormScope("staff_unavailability");
  } else {
    form.action = `/admin/events/${id}`;
    setFormScope("event");
  }

  // Add PATCH method
  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "patch";
  form.appendChild(methodInput);

  // 2. SET MODAL TITLE
  document.getElementById("eventModalLabel").textContent = isUnavailability
    ? "Edit Unavailability"
    : "Edit Event";

  // 3. HANDLE EVENT TYPE DROPDOWN
  const eventTypeSelect = document.getElementById("event_type_select");
  if (eventTypeSelect) {
    if (isUnavailability) {
      eventTypeSelect.value = "unavailability";
      setEventTypeLock(true);
    } else {
      eventTypeSelect.value = event.extendedProps.eventType || "other";
      setEventTypeLock(false);

      // Clone and add listener
      const newSelect = eventTypeSelect.cloneNode(true);
      eventTypeSelect.parentNode.replaceChild(newSelect, eventTypeSelect);
      newSelect.value = event.extendedProps.eventType || "other";
      newSelect.addEventListener("change", (e) => {
        toggleFormMode(e.target.value);
      });
    }
  }

  // Trigger form mode
  toggleFormMode(
    isUnavailability
      ? "unavailability"
      : event.extendedProps.eventType || "other",
  );

  // TIME FIELDS
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

  // TITLE & DESCRIPTION
  document.getElementById("title").value =
    event.title.replace(/✎/g, "").trim() || "";
  document.getElementById("description").value =
    event.extendedProps.description || "";

  // RECURRENCE
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
        if (rule.options.byweekday) {
          rule.options.byweekday.forEach((day) => {
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
        }
        break;
      case RRule.MONTHLY:
        frequency.value = "MONTHLY";
        break;
    }

    if (rule.options.until) {
      untilInput.value = toLocalDateString(rule.options.until);
    }
    ruleField.value = rule.toString();
  }

  // TRAINING FIELDS
  const trainingFields = document.getElementById("training-fields");
  if (event.extendedProps.eventType === "training") {
    trainingFields.style.display = "block";
    document.getElementById("training_select").value =
      event.extendedProps.trainingId || "";
    document.getElementById("language_select").value =
      event.extendedProps.language || "";
    document.getElementById("course_select").value =
      event.extendedProps.course_name?.id || "";
  }

  // STAFF SELECTION
  const staffSelect = document.getElementById("staff_select");
  staffSelect.innerHTML = "";

  const assignedUsers = isUnavailability
    ? [
        {
          id: event.extendedProps.userId,
          name: event.extendedProps.name?.split("(")[0]?.trim() || "User",
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

  // POSITION SAVE BUTTON
  const hasRecurrence = event.recurringDef || rruleData;
  positionSaveButton(hasRecurrence, true);

  // HANDLE PUBLISH BUTTON (events only)
  const publishForm = document.getElementById("publish_form");
  if (event.extendedProps.draft && !isUnavailability) {
    publishForm.action = `/admin/events/${id}/publish`;
    publishForm.style.display = "block";
  } else {
    publishForm.style.display = "none";
  }

  // HANDLE DELETE BUTTONS
  document.getElementById("publish_and_delete_forms").style.display = "flex";

  const singleForm = document.getElementById("delete_single_form");
  const followingForm = document.getElementById("delete_following_form");
  const allForm = document.getElementById("delete_all_form");

  if (hasRecurrence) {
    followingForm.style.display = "block";
    allForm.style.display = "block";
  } else {
    followingForm.style.display = "none";
    allForm.style.display = "none";
  }

  // Set start_date for deletion
  const startDateValue = parseLocalDatetimeString(
    eventImpl.startStr,
  ).toISOString();
  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = startDateValue;
  });

  // Set form actions
  if (isUnavailability) {
    singleForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
    followingForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
    allForm.action = `/staff/unavailabilities/${eventImpl.id}/delete_with_scope`;
  } else {
    singleForm.action = `/admin/events/${id}/delete_with_scope`;
    followingForm.action = `/admin/events/${id}/delete_with_scope`;
    allForm.action = `/admin/events/${id}/delete_with_scope`;
  }

  // SHOW MODAL
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

  // Click the add button then call addEventClick
  document.getElementById("addEventButton").click();
  addEventClick();
}
