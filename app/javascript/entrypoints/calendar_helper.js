import { RRule } from "rrule";
import { Modal } from "bootstrap";
import TomSelect from "tom-select";

// Global variables for this module
let staffSelectInstance = null;
let allStaffData = [];

/*
 * Converts a Date object to a local datetime string in the format YYYY-MM-DDTHH:MM
 */
export function toLocalDatetimeString(date) {
  if (!date) return null;
  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function toLocalDateString(date) {
  if (!date) return null;
  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function parseLocalDatetimeString(value) {
  if (!value) return new Date();
  return new Date(value);
}

// ============================================================
// STAFF DROPDOWN & SEARCH LOGIC
// ============================================================

export function initStaffLoader(data) {
  allStaffData = data.map((s) => ({ value: s.id, text: s.name }));
  initStaffSelect(true);
}

function initStaffSelect(isMultiple) {
  const staffSelect = document.getElementById("staff_select");
  if (!staffSelect) return;

  if (staffSelectInstance) {
    staffSelectInstance.destroy();
    staffSelectInstance = null;
  }

  staffSelect.innerHTML = "";
  staffSelect.multiple = isMultiple;

  staffSelectInstance = new TomSelect(staffSelect, {
    options: allStaffData,
    items: [],
    plugins: isMultiple ? ["remove_button"] : [],
    maxItems: isMultiple ? null : 1,
    placeholder: isMultiple
      ? "Search for staff..."
      : "Select a staff member...",
    valueField: "value",
    labelField: "text",
    searchField: ["text"],
    create: false,
    render: {
      option: function (data, escape) {
        return "<div>" + escape(data.text) + "</div>";
      },
      item: function (data, escape) {
        return "<div>" + escape(data.text) + "</div>";
      },
    },
  });
}

// ============================================================
// CATEGORY SWITCHER & FORM HANDLING
// ============================================================

let originalFormAction = null;
const unavailabilityFormAction = "/admin/staff_unavailabilities";

export function initCategorySwitcher() {
  const categoryEvent = document.getElementById("category_event");
  const categoryUnavailability = document.getElementById(
    "category_unavailability",
  );
  const form = document.getElementById("eventForm");

  if (!categoryEvent || !categoryUnavailability || !form) return;

  originalFormAction = form.action;

  categoryEvent.addEventListener("change", function () {
    if (this.checked) switchToEventMode();
  });

  categoryUnavailability.addEventListener("change", function () {
    if (this.checked) switchToUnavailabilityMode();
  });

  form.addEventListener("submit", handleFormSubmit);
}

function switchToEventMode() {
  const form = document.getElementById("eventForm");
  const eventOnlyFields = document.getElementById("event_only_fields");
  const staffSelectLabel = document.getElementById("staff_select_label");
  const staffSelectHelp = document.getElementById("staff_select_help");
  const staffSelect = document.getElementById("staff_select");
  const eventTypeSelect = document.getElementById("event_type_select");
  const modalTitle = document.getElementById("eventModalLabel");
  const accordion = document.getElementById("accordion");

  if (eventOnlyFields) eventOnlyFields.style.display = "block";
  if (accordion) accordion.style.display = "block";
  if (staffSelectLabel) staffSelectLabel.textContent = "Assigned Staff";

  if (staffSelect) {
    staffSelect.name = "staff_select[]";
    staffSelect.required = false;
  }
  if (staffSelectHelp) staffSelectHelp.classList.add("d-none");

  if (eventTypeSelect) eventTypeSelect.required = true;

  if (modalTitle && modalTitle.textContent.includes("Unavailability")) {
    modalTitle.textContent = modalTitle.textContent.replace(
      "Unavailability",
      "Event",
    );
  }

  if (form && originalFormAction) {
    form.action = originalFormAction;
  }

  const methodInput = form?.querySelector('input[name="_method"]');
  if (
    methodInput &&
    !document.getElementById("eventModalLabel")?.textContent.includes("Edit")
  ) {
    methodInput.remove();
  }

  document
    .getElementById("unavailability_staff_error")
    ?.classList.add("d-none");

  initStaffSelect(true);
}

function switchToUnavailabilityMode() {
  const form = document.getElementById("eventForm");
  const eventOnlyFields = document.getElementById("event_only_fields");
  const staffSelectLabel = document.getElementById("staff_select_label");
  const staffSelectHelp = document.getElementById("staff_select_help");
  const staffSelect = document.getElementById("staff_select");
  const eventTypeSelect = document.getElementById("event_type_select");
  const modalTitle = document.getElementById("eventModalLabel");
  const accordion = document.getElementById("accordion");

  if (eventOnlyFields) eventOnlyFields.style.display = "none";
  if (accordion) accordion.style.display = "none";
  if (staffSelectLabel) staffSelectLabel.textContent = "Staff Member";

  if (staffSelect) {
    staffSelect.name = "staff_unavailability[user_id]";
    staffSelect.required = true;
  }
  if (staffSelectHelp) staffSelectHelp.classList.remove("d-none");

  if (eventTypeSelect) eventTypeSelect.required = false;

  if (modalTitle && modalTitle.textContent.includes("Event")) {
    modalTitle.textContent = modalTitle.textContent.replace(
      "Event",
      "Unavailability",
    );
  }

  if (form) {
    form.action = unavailabilityFormAction;
  }

  initStaffSelect(false);
}

function handleFormSubmit(e) {
  const isUnavailability = document.getElementById(
    "category_unavailability",
  )?.checked;
  const errorDiv = document.getElementById("unavailability_staff_error");

  // 1. Calculate UTC times from Local inputs (FIXES "no time information" ERROR)
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");
  const utcStart = document.getElementById("utc_start_time");
  const utcEnd = document.getElementById("utc_end_time");

  if (startField && startField.value) {
    utcStart.value = new Date(startField.value).toISOString();
  }
  if (endField && endField.value) {
    utcEnd.value = new Date(endField.value).toISOString();
  }

  // 2. Unavailability specific logic
  if (isUnavailability) {
    // Validate Staff Selection
    const selectedStaff = staffSelectInstance
      ? staffSelectInstance.getValue()
      : "";

    if (!selectedStaff) {
      e.preventDefault();
      errorDiv?.classList.remove("d-none");
      return false;
    }
    errorDiv?.classList.add("d-none");

    // Rename fields so the Controller params work
    const rruleField = document.getElementById("recurrence_rule_field");
    const titleField = document.getElementById("title");
    const descField = document.getElementById("description");

    if (utcStart) utcStart.name = "staff_unavailability[utc_start_time]";
    if (utcEnd) utcEnd.name = "staff_unavailability[utc_end_time]";
    if (rruleField) rruleField.name = "staff_unavailability[recurrence_rule]";
    if (titleField) titleField.name = "staff_unavailability[title]";
    if (descField) descField.name = "staff_unavailability[description]";
  }
}

export function setModalCategory(category) {
  const categoryEvent = document.getElementById("category_event");
  const categoryUnavailability = document.getElementById(
    "category_unavailability",
  );

  if (category === "unavailability") {
    if (categoryUnavailability) categoryUnavailability.checked = true;
    switchToUnavailabilityMode();
  } else {
    if (categoryEvent) categoryEvent.checked = true;
    switchToEventMode();
  }
}

export function setCategorySelectorVisible(visible) {
  const container = document.getElementById("category_selector_container");
  if (container) {
    container.style.display = visible ? "block" : "none";
  }
}

export function resetModalForm() {
  const form = document.getElementById("eventForm");
  if (!form) return;

  form.reset();
  initStaffSelect(true);

  setModalCategory("event");
  setCategorySelectorVisible(true);

  if (originalFormAction) {
    form.action = originalFormAction;
  }

  form.querySelector('input[name="_method"]')?.remove();

  // Reset names back to Event defaults
  const utcStart = document.getElementById("utc_start_time");
  const utcEnd = document.getElementById("utc_end_time");
  const rruleField = document.getElementById("recurrence_rule_field");
  const titleField = document.getElementById("title");
  const descField = document.getElementById("description");

  if (utcStart) utcStart.name = "event[utc_start_time]";
  if (utcEnd) utcEnd.name = "event[utc_end_time]";
  if (rruleField) rruleField.name = "event[recurrence_rule]";
  if (titleField) titleField.name = "event[title]";
  if (descField) descField.name = "event[description]";

  document
    .getElementById("unavailability_staff_error")
    ?.classList.add("d-none");
  document.getElementById("time_error")?.classList.add("d-none");
  document.getElementById("day_freq_error")?.classList.add("d-none");

  document.getElementById("recurrence_frequency").value = "";
  document.getElementById("recurrence_options").style.display = "none";
  document.getElementById("weekly_options").style.display = "none";
  document
    .querySelectorAll(".dayCheckbox")
    .forEach((cb) => (cb.checked = false));

  document.getElementById("eventModalLabel").textContent = "Add Event";
  const saveButton = document.getElementById("save_button");
  if (saveButton) saveButton.value = "Save Draft";

  document.getElementById("modal_buttons").style.display = "flex";
  document.getElementById("publish_and_delete_forms").style.display = "none";
  document.getElementById("update_dropdown").style.display = "none";

  document.getElementById("event_only_fields").style.display = "block";
  document.getElementById("accordion").style.display = "block";
  document.getElementById("training-fields").style.display = "none";
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

  setModalCategory("event");
  setCategorySelectorVisible(true);

  if (staffSelectInstance) staffSelectInstance.clear();
}

export function eventClick(eventImpl) {
  const event = eventImpl._def;
  const extendedProps = event.extendedProps;

  if (extendedProps.type === "unavailability") {
    unavailabilityClick(eventImpl);
    return;
  }

  const id = eventImpl.id.replace("event-", "");
  if (!extendedProps.eventType) return;

  setModalCategory("event");
  setCategorySelectorVisible(false);

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
    extendedProps.description || "";

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
          if (dayCheckboxes[day + 1]) dayCheckboxes[day + 1].checked = true;
          else dayCheckboxes[0].checked = true;
        });
        break;
      case RRule.MONTHLY:
        frequency.value = "MONTHLY";
        break;
    }
    untilInput.value = toLocalDateString(rule.options.until);
    ruleField.value = rule.toString();
  }

  const eventTypeSelect = document.getElementById("event_type_select");
  eventTypeSelect.value = extendedProps.eventType || "other";

  const trainingFields = document.getElementById("training-fields");
  if (eventTypeSelect.value === "training") {
    trainingFields.style.display = "";
    document.getElementById("training_select").value =
      extendedProps.trainingId || null;
    document.getElementById("language_select").value =
      extendedProps.language || null;
    document.getElementById("course_select").value =
      extendedProps.course_name?.id || null;
  } else {
    trainingFields.style.display = "none";
  }

  if (staffSelectInstance) {
    staffSelectInstance.clear();
    const assignedStaff = extendedProps.assignedUsers || [];
    assignedStaff.forEach((staff) => {
      staffSelectInstance.addItem(staff.id);
    });
  }

  document.getElementById("eventModalLabel").textContent = "Edit Event";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Update";

  if (event.recurringDef) {
    document.getElementById("update_dropdown_items").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "block";
  } else {
    document.getElementById("modal_buttons").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "none";
  }

  const publishForm = document.getElementById("publish_form");
  if (extendedProps.draft) {
    publishForm.action = `/admin/events/${id}/publish`;
    publishForm.style.display = "block";
  } else {
    publishForm.style.display = "none";
  }

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

  const modal = new Modal(document.getElementById("eventModal"));
  modal.show();
}

export function unavailabilityClick(eventImpl) {
  const event = eventImpl._def;
  const extendedProps = event.extendedProps;
  const id = extendedProps.dbId || eventImpl.id;

  setModalCategory("unavailability");
  setCategorySelectorVisible(false);

  const form = document.querySelector("#eventModal form");
  form.action = `/admin/staff_unavailabilities/${id}`;
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

  document.getElementById("title").value = event.title || "Unavailable";
  document.getElementById("description").value =
    extendedProps.description || "";

  if (staffSelectInstance && extendedProps.userId) {
    staffSelectInstance.clear();
    staffSelectInstance.addItem(extendedProps.userId);
  }

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
          if (dayCheckboxes[day + 1]) dayCheckboxes[day + 1].checked = true;
          else dayCheckboxes[0].checked = true;
        });
        break;
      case RRule.MONTHLY:
        frequency.value = "MONTHLY";
        break;
    }
    untilInput.value = toLocalDateString(rule.options.until);
    ruleField.value = rule.toString();
  }

  document.getElementById("eventModalLabel").textContent =
    "Edit Unavailability";
  const saveButton = document.getElementById("save_button");
  saveButton.value = "Update";

  const hasRecurrence = event.recurringDef || extendedProps.rrule;
  if (hasRecurrence) {
    document.getElementById("update_dropdown_items").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "block";
  } else {
    document.getElementById("modal_buttons").appendChild(saveButton);
    document.getElementById("update_dropdown").style.display = "none";
  }

  document.getElementById("publish_form").style.display = "none";
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

  document.querySelectorAll(".delete_start_date").forEach((e) => {
    e.value = parseLocalDatetimeString(eventImpl.startStr).toISOString();
  });

  singleForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;
  followingForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;
  allForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;

  const modal = new Modal(document.getElementById("eventModal"));
  modal.show();
}

export function eventCreate(info) {
  resetModalForm();

  document.getElementById("start_time_field").value = toLocalDatetimeString(
    new Date(info.startStr),
  );
  document.getElementById("end_time_field").value = toLocalDatetimeString(
    new Date(info.endStr),
  );
  document.getElementById("training-fields").style.display = "none";

  document.getElementById("addEventButton").click();
  addEventClick();
}
