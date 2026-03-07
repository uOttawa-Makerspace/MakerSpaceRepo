import { RRule } from "rrule";
import { Modal } from "bootstrap";

const CALENDAR_TIMEZONE = "America/Toronto";

/*
 * Converts a Date object to a datetime string in the CALENDAR timezone
 * in the format YYYY-MM-DDTHH:MM (for datetime-local inputs)
 */
export function toLocalDatetimeString(date) {
  if (!date) return null;

  const formatter = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: CALENDAR_TIMEZONE,
  });

  const parts = formatter.formatToParts(date);
  const get = (type) => parts.find((p) => p.type === type).value;

  let hour = get("hour");
  if (hour === "24") hour = "00"; // Intl may return 24 for midnight

  return `${get("year")}-${get("month")}-${get("day")}T${hour}:${get("minute")}`;
}

/*
 * Converts a Date object to a date string in the CALENDAR timezone
 * in the format YYYY-MM-DD
 */
export function toLocalDateString(date) {
  if (!date) return null;

  const formatter = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone: CALENDAR_TIMEZONE,
  });

  const parts = formatter.formatToParts(date);
  const get = (type) => parts.find((p) => p.type === type).value;

  return `${get("year")}-${get("month")}-${get("day")}`;
}

/*
 * Parses a datetime string (possibly with timezone offset) and returns a Date.
 */
export function parseLocalDatetimeString(value) {
  if (!value) return new Date();
  return new Date(value);
}

/*
 * Converts a datetime-local value (interpreted as CALENDAR_TIMEZONE wall-clock time)
 * to a UTC ISO string for server submission.
 */
function datetimeLocalToUTC(datetimeLocalValue) {
  if (!datetimeLocalValue) return "";

  const [datePart, timePart] = datetimeLocalValue.split("T");
  const [year, month, day] = datePart.split("-").map(Number);
  const [hours, minutes] = timePart.split(":").map(Number);

  // Create a Date near the target to determine the timezone offset
  const approxDate = new Date(Date.UTC(year, month - 1, day, hours, minutes));

  // Get America/Toronto offset at this instant (in ms)
  const offsetMs = getTimezoneOffsetMs(CALENDAR_TIMEZONE, approxDate);

  // wall-clock time minus offset = UTC
  // e.g., 13:00 EDT (offset +4h) → UTC = 13:00 - (+4h) = 17:00 UTC... wait
  // Actually offset is (local - UTC). So if EDT is UTC-4, offset = -4h.
  // UTC = wall-clock - offset → UTC = 13:00 - (-4h) = 17:00 ✓
  const utcMs = Date.UTC(year, month - 1, day, hours, minutes) - offsetMs;

  return new Date(utcMs).toISOString();
}

/*
 * Returns the offset (local - UTC) in milliseconds for a given timezone at a given instant.
 * e.g., America/Toronto in EST: returns -5*3600*1000 = -18000000
 *       America/Toronto in EDT: returns -4*3600*1000 = -14400000
 */
function getTimezoneOffsetMs(timezone, date) {
  const utcStr = date.toLocaleString("en-US", { timeZone: "UTC" });
  const tzStr = date.toLocaleString("en-US", { timeZone: timezone });
  return new Date(tzStr) - new Date(utcStr);
}

/*
 * Syncs the hidden UTC fields from the visible datetime-local fields.
 * Called on form submission and whenever the user changes the time inputs.
 */
function syncUTCFields() {
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");
  const utcStartField = document.getElementById("utc_start_time");
  const utcEndField = document.getElementById("utc_end_time");

  if (startField && utcStartField) {
    utcStartField.value = datetimeLocalToUTC(startField.value);
  }
  if (endField && utcEndField && !endField.disabled) {
    utcEndField.value = datetimeLocalToUTC(endField.value);
  } else if (endField && utcEndField && endField.disabled) {
    // All-day: end time field is disabled, compute from start + 1 day
    utcEndField.value = datetimeLocalToUTC(endField.value);
  }
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

  // Clear hidden UTC fields
  const utcStart = document.getElementById("utc_start_time");
  const utcEnd = document.getElementById("utc_end_time");
  if (utcStart) utcStart.value = "";
  if (utcEnd) utcEnd.value = "";

  setFormScope("event");
}

// -------------------
// Helper to switch input names between "event[name]" and "staff_unavailability[name]"
// The visible start/end fields do NOT get a submission name —
// only the hidden utc_ fields are submitted.
// -------------------
function setFormScope(scope) {
  const form = document.querySelector("#eventModal form");
  if (!form) return;

  // Visible time fields: remove name so they don't submit
  // (UTC hidden fields carry the correct values)
  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");
  if (startTimeField) startTimeField.removeAttribute("name");
  if (endTimeField) endTimeField.removeAttribute("name");

  // Hidden fields and other inputs that DO get submitted
  const fieldMappings = {
    utc_start_time: "utc_start_time",
    utc_end_time: "utc_end_time",
    recurrence_rule_field: "recurrence_rule",
    title: "title",
    description: "description",
  };

  // Update specific fields
  Object.entries(fieldMappings).forEach(([fieldId, paramName]) => {
    const field = document.getElementById(fieldId);
    if (field) {
      field.name = `${scope}[${paramName}]`;
    }
  });

  // Handle staff select
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
// Set up form submit handler (once)
// -------------------
let formHandlerAttached = false;
function ensureFormHandler() {
  if (formHandlerAttached) return;
  const form = document.querySelector("#eventModal form");
  if (!form) return;

  form.addEventListener("submit", () => {
    syncUTCFields();
  });

  // Also sync when user manually edits time fields
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");
  if (startField) startField.addEventListener("change", syncUTCFields);
  if (endField) endField.addEventListener("change", syncUTCFields);

  formHandlerAttached = true;
}

// -------------------
// Full Calendar Event Helpers
// -------------------
export function addEventClick() {
  // Reset everything first
  resetModalState();

  // Populate staff options if needed
  populateStaffSelect();
  ensureFormHandler();

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
  ensureFormHandler();

  const form = document.querySelector("#eventModal form");

  // FORM ACTION & METHOD
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

  // EVENT TYPE DROPDOWN
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

  // TIME FIELDS — use FullCalendar's Date objects directly
  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");
  const allDayCheckbox = document.getElementById("all_day_checkbox");
  const utcStartField = document.getElementById("utc_start_time");
  const utcEndField = document.getElementById("utc_end_time");

  if (eventImpl.allDay) {
    allDayCheckbox.checked = true;

    // For all-day events, startStr is "YYYY-MM-DD" (no time component)
    // Use the date string directly — no Date object needed
    const startDateStr = eventImpl.startStr.split("T")[0];
    startTimeField.value = `${startDateStr}T00:00`;

    const endDateStr = eventImpl.endStr
      ? eventImpl.endStr.split("T")[0]
      : startDateStr;
    endTimeField.value = `${endDateStr}T00:00`;
    endTimeField.disabled = true;

    // Set UTC hidden fields
    utcStartField.value = datetimeLocalToUTC(startTimeField.value);
    utcEndField.value = datetimeLocalToUTC(endTimeField.value);
  } else {
    allDayCheckbox.checked = false;

    // startStr includes timezone offset: "2025-03-09T13:00:00-04:00"
    // new Date() correctly parses this to the right instant
    const start = new Date(eventImpl.startStr);
    const end = eventImpl.end
      ? new Date(eventImpl.endStr)
      : new Date(start.getTime() + 3600000);

    // Display in calendar timezone
    startTimeField.value = toLocalDatetimeString(start);
    endTimeField.value = toLocalDatetimeString(end);
    endTimeField.disabled = false;

    // Hidden fields get proper UTC
    utcStartField.value = start.toISOString();
    utcEndField.value = end.toISOString();
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
            const cb = document.getElementById(`day_${dayMap[day]}`);
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

  const startDateValue = new Date(eventImpl.startStr).toISOString();
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
  // FullCalendar select gives startStr/endStr with timezone offset
  // e.g., "2025-03-09T13:00:00-04:00"
  const startDate = new Date(info.startStr);
  const endDate = new Date(info.endStr);

  // Display in calendar timezone
  document.getElementById("start_time_field").value =
    toLocalDatetimeString(startDate);
  document.getElementById("end_time_field").value =
    toLocalDatetimeString(endDate);

  // Set hidden UTC fields immediately
  document.getElementById("utc_start_time").value = startDate.toISOString();
  document.getElementById("utc_end_time").value = endDate.toISOString();

  document.getElementById("addEventButton").click();
  addEventClick();
}
