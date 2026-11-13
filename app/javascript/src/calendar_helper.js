import { RRule } from "rrule";
import { Modal } from "bootstrap";

import {
  dateValue,
  fieldValue,
  instantFromCalendar,
  instantToWall,
  storedRule,
  wallFromCalendar,
  wallToInstant,
} from "./recurrence";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

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
  document.getElementById("unpublish_form").style.display = "none";
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
// Full Calendar Event Helpers
// -------------------
export function addEventClick() {
  // Reset everything first
  resetModalState();

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

// manage_calendar_events.js marks the modal ready once its handlers are
// attached; until then (or after a failed load) no entry point may open it.
export function eventModalReady() {
  return document.getElementById("eventModal")?.dataset.ready === "true";
}

export function eventClick(eventImpl) {
  if (!eventModalReady()) return;
  openEventForEditing(eventImpl);
}

// The end of an event the calendar gives without one: the next day for an
// all-day event, otherwise an hour after the start.
function defaultEnd(start, allDay) {
  if (allDay) return start + DAY_MS;
  return instantToWall(wallToInstant(start) + HOUR_MS);
}

// The title to edit: the stored one when the feed sends it (an entry with no
// title sends null, which is an empty field), otherwise the calendar's label
// without its pencil mark.
function storedTitle(event) {
  if ("title" in event.extendedProps) return event.extendedProps.title ?? "";
  return event.title.replace(/✎/g, "").trim() || "";
}

const WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

// The repeat of the clicked entry as the dialog shows it ({ frequency,
// weekdays, until }), or null for a single entry: what the feed sent
// (unavailabilities), or what the rule the calendar repeats an event by says
// (the rrule plugin's series definition).
function seriesOf(event) {
  if ("series" in event.extendedProps) return event.extendedProps.series;
  const options = event.recurringDef?.typeData.rruleSet._rrule[0].origOptions;
  return options ? seriesFromRule(options) : null;
}

function seriesFromRule(options) {
  const { freq, byweekday, until } = new RRule(options).options;
  return {
    frequency: RRule.FREQUENCIES[freq],
    weekdays: (byweekday || []).map((day) => WEEKDAYS[day]),
    until: until && dateValue(until.getTime()),
  };
}

// The repeat fields of a series, and the rule they make from the clicked
// occurrence's start (wall time), as it is stored.
function fillRepeatFields({ frequency, weekdays, until }, startWall) {
  const untilDate = until || "";
  const weekly = frequency === "WEEKLY";
  document.querySelector("#recurrence_rule_field").value = storedRule(
    { freq: RRule[frequency], byweekday: weekdays.map((day) => RRule[day]) },
    startWall,
    untilDate,
  );
  document.querySelector("#recurrence_options").style.display = "block";
  document.querySelector("#recurrence_frequency").value = frequency;
  document.querySelector("#weekly_options").style.display = weekly
    ? "block"
    : "none";
  weekdays.forEach((day) => {
    const box = document.getElementById(`day_${day}`);
    if (box) box.checked = weekly;
  });
  document.querySelector("#recurrence_until").value = untilDate;
}

function openEventForEditing(eventImpl) {
  const event = eventImpl._def;
  const id = eventImpl.id.replace("event-", "");
  const isUnavailability = event.extendedProps.eventType === "unavailability";
  const [recordPath, scope] = isUnavailability
    ? [
        `/staff/unavailabilities/${event.extendedProps.recordId}`,
        "staff_unavailability",
      ]
    : [`/admin/events/${id}`, "event"];

  // Only edit events with an eventType
  if (!event.extendedProps.eventType) return;

  // Reset modal first
  resetModalState();

  const form = document.querySelector("#eventModal form");

  // SETUP FORM ACTION & METHOD
  form.action = recordPath;
  setFormScope(scope);

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

  // TIME FIELDS, in Toronto wall-clock time like the calendar
  const startTimeField = document.getElementById("start_time_field");
  const endTimeField = document.getElementById("end_time_field");
  const allDayCheckbox = document.getElementById("all_day_checkbox");

  const start = wallFromCalendar(eventImpl.startStr);
  allDayCheckbox.checked = eventImpl.allDay;
  endTimeField.disabled = eventImpl.allDay;
  startTimeField.value = fieldValue(start);
  endTimeField.value = fieldValue(
    eventImpl.end
      ? wallFromCalendar(eventImpl.endStr)
      : defaultEnd(start, eventImpl.allDay),
  );

  // TITLE & DESCRIPTION
  document.getElementById("title").value = storedTitle(event);
  document.getElementById("description").value =
    event.extendedProps.description || "";

  // RECURRENCE
  const series = seriesOf(event);
  if (series) fillRepeatFields(series, start);

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
  const hasRecurrence = Boolean(series);
  positionSaveButton(hasRecurrence, true);

  // HANDLE PUBLISH BUTTON (events only)
  const publishForm = document.getElementById("publish_form");
  if (event.extendedProps.draft && !isUnavailability) {
    publishForm.action = `/admin/events/${id}/publish`;
    publishForm.style.display = "block";
  } else {
    publishForm.style.display = "none";
  }

  // HANDLE UNPUBLISH BUTTON (published events only)
  const unpublishForm = /** @type {HTMLFormElement} */ (
    document.getElementById("unpublish_form")
  );
  if (!event.extendedProps.draft && !isUnavailability) {
    unpublishForm.action = `/admin/events/${id}/publication`;
    unpublishForm.style.display = "block";
  } else {
    unpublishForm.style.display = "none";
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

  // Set start_date for deletion: the instant of the clicked occurrence, as the
  // feed sent it (unavailabilities) or as the calendar draws it (events)
  const startDateValue =
    event.extendedProps.occurrenceStart ??
    new Date(instantFromCalendar(eventImpl.startStr)).toISOString();
  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = startDateValue;
  });

  // Set form actions
  singleForm.action =
    followingForm.action =
    allForm.action =
      `${recordPath}/delete_with_scope`;

  // SHOW MODAL
  const modal = new Modal(document.getElementById("eventModal"));
  modal.show();
}

export function eventCreate(info) {
  if (!eventModalReady()) {
    info.view.calendar.unselect(); // drop the highlight of the dragged range
    return;
  }

  document.getElementById("start_time_field").value = fieldValue(
    wallFromCalendar(info.startStr),
  );
  document.getElementById("end_time_field").value = fieldValue(
    wallFromCalendar(info.endStr),
  );

  // Click the add button then call addEventClick
  document.getElementById("addEventButton").click();
  addEventClick();
}
