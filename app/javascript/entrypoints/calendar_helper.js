import { RRule } from "rrule";
import { Modal, Collapse } from "bootstrap";
import TomSelect from "tom-select";

// Global variables
let staffSelectInstance = null;
let allStaffData = [];

// ============================================================
// DATE & TIME HELPERS
// ============================================================

export function formatCalendarDateForInput(dateStr) {
  if (!dateStr) return "";
  if (dateStr.indexOf("T") === -1) return dateStr;
  return dateStr.substring(0, 16);
}

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

  // 1. Destroy existing instance
  if (staffSelectInstance) {
    staffSelectInstance.destroy();
    staffSelectInstance = null;
  }

  // 2. Clear content and set multiple attribute
  staffSelect.innerHTML = "";
  staffSelect.multiple = isMultiple;

  // 3. Re-initialize Tom Select
  staffSelectInstance = new TomSelect(staffSelect, {
    options: allStaffData,
    items: [],
    // We add 'remove_button' even for single select if you want the design to look similar
    // though usually single select behaves like a dropdown.
    plugins: isMultiple ? ["remove_button"] : [],
    maxItems: isMultiple ? null : 1,
    placeholder: "Select staff...", // Common placeholder
    valueField: "value",
    labelField: "text",
    searchField: ["text"],
    create: false,
    // This ensures the input style matches Bootstrap's form-control
    controlInput: "<input>",
    render: {
      option: function (data, escape) {
        return "<div>" + escape(data.text) + "</div>";
      },
      item: function (data, escape) {
        return "<div>" + escape(data.text) + "</div>";
      },
    },
    onInitialize: function () {
      // Fix: Ensure the visual control does not inherit 'is-invalid' class from the underlying select
      this.wrapper.classList.remove("is-invalid");
      this.control.classList.remove("is-invalid");
    },
  });
}

// ============================================================
// FORM HANDLING & TOGGLES
// ============================================================

let originalFormAction = null;
const unavailabilityFormAction = "/admin/staff_unavailabilities";

export function initCategorySwitcher() {
  const categoryEvent = document.getElementById("category_event");
  const categoryUnavailability = document.getElementById(
    "category_unavailability",
  );
  const form = document.getElementById("eventForm");

  initAllDayToggle();
  initEventTypeToggle();
  initRecurrenceLogic();

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

// Clears Red Validation Box
function clearFormValidation() {
  const form = document.getElementById("eventForm");
  const errorDiv = document.getElementById("unavailability_staff_error");

  // Remove Bootstrap validation state
  if (form) form.classList.remove("was-validated");

  // Hide manual error message
  if (errorDiv) errorDiv.classList.add("d-none");

  // Remove red border from Tom Select if it exists
  if (staffSelectInstance) {
    staffSelectInstance.wrapper.classList.remove("is-invalid");
    staffSelectInstance.control.classList.remove("is-invalid");
  }
}

function initAllDayToggle() {
  const allDayCheckbox = document.getElementById("all_day_checkbox");
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");

  if (!allDayCheckbox || !startField || !endField) return;

  allDayCheckbox.addEventListener("change", function () {
    if (this.checked) {
      const datePart = startField.value ? startField.value.split("T")[0] : "";
      startField.type = "date";
      endField.type = "date";
      if (datePart) {
        startField.value = datePart;
        endField.value = datePart;
      }
    } else {
      const startVal = startField.value ? startField.value + "T09:00" : "";
      const endVal = endField.value ? endField.value + "T17:00" : "";
      startField.type = "datetime-local";
      endField.type = "datetime-local";
      if (startField.value.indexOf("T") === -1 && startField.value !== "")
        startField.value = startVal;
      if (endField.value.indexOf("T") === -1 && endField.value !== "")
        endField.value = endVal;
    }
  });

  startField.addEventListener("change", function () {
    if (allDayCheckbox.checked && startField.value) {
      endField.value = startField.value;
    }
  });
}

function initEventTypeToggle() {
  const eventTypeSelect = document.getElementById("event_type_select");
  const trainingFields = document.getElementById("training-fields");

  if (!eventTypeSelect || !trainingFields) return;

  eventTypeSelect.addEventListener("change", function () {
    if (this.value === "training") {
      trainingFields.style.display = "block";
    } else {
      trainingFields.style.display = "none";
      document.getElementById("training_select").value = "";
      document.getElementById("language_select").value = "";
      document.getElementById("course_select").value = "";
    }
  });
}

function initRecurrenceLogic() {
  const freqSelect = document.getElementById("recurrence_frequency");
  const optionsDiv = document.getElementById("recurrence_options");
  const weeklyDiv = document.getElementById("weekly_options");

  if (!freqSelect || !optionsDiv || !weeklyDiv) return;

  freqSelect.addEventListener("change", function () {
    const val = this.value;

    if (val === "") {
      // Does not repeat
      optionsDiv.style.display = "none";
      weeklyDiv.style.display = "none";
    } else {
      // Show general options (Until date)
      optionsDiv.style.display = "block";

      // Show weekly checkboxes only if Weekly
      if (val === "WEEKLY") {
        weeklyDiv.style.display = "block";
      } else {
        weeklyDiv.style.display = "none";
      }
    }
  });
}

function switchToEventMode() {
  clearFormValidation();

  const form = document.getElementById("eventForm");
  const staffSelectLabel = document.getElementById("staff_select_label");
  const staffSelectHelp = document.getElementById("staff_select_help");
  const staffSelect = document.getElementById("staff_select");
  const eventTypeSelect = document.getElementById("event_type_select");
  const modalTitle = document.getElementById("eventModalLabel");
  const saveButton = document.getElementById("save_button");

  const collapseEl = document.getElementById("event_mode_content");
  if (collapseEl && !collapseEl.classList.contains("show")) {
    const bsCollapse = new Collapse(collapseEl, { toggle: false });
    bsCollapse.show();
  }

  if (saveButton) {
    saveButton.value = "Save Draft";
    saveButton.classList.remove("btn-info");
    saveButton.classList.add("btn-success");
  }

  if (staffSelectLabel) staffSelectLabel.textContent = "Assigned Staff";

  if (staffSelect) {
    staffSelect.name = "staff_select[]";
    staffSelect.required = false; // Not required in Event mode
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

  initStaffSelect(true);
}

function switchToUnavailabilityMode() {
  clearFormValidation();

  const form = document.getElementById("eventForm");
  const staffSelectLabel = document.getElementById("staff_select_label");
  const staffSelectHelp = document.getElementById("staff_select_help");
  const staffSelect = document.getElementById("staff_select");
  const eventTypeSelect = document.getElementById("event_type_select");
  const modalTitle = document.getElementById("eventModalLabel");
  const saveButton = document.getElementById("save_button");

  const collapseEl = document.getElementById("event_mode_content");
  if (collapseEl) {
    const bsCollapse = new Collapse(collapseEl, { toggle: false });
    bsCollapse.hide();
  }

  if (saveButton) {
    saveButton.value = "Publish";
    saveButton.classList.remove("btn-success");
    saveButton.classList.add("btn-info");
  }

  if (staffSelectLabel) staffSelectLabel.textContent = "Staff Member";

  if (staffSelect) {
    staffSelect.name = "staff_unavailability[user_id]";
    // Note: We set required=true, but we cleared validation above,
    // so it won't turn red until the user clicks submit and it fails.
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
  const form = document.getElementById("eventForm");

  if (form) form.classList.add("was-validated");

  // --- 1. GENERATE RECURRENCE RULE ---
  // We must calculate the RRule string from the visible inputs and put it
  // into the hidden field before Rails processes it.
  const freq = document.getElementById("recurrence_frequency").value;
  const ruleField = document.getElementById("recurrence_rule_field");

  if (freq) {
    const rruleOptions = {
      freq: RRule[freq], // Maps "DAILY" -> RRule.DAILY, etc.
    };

    // Handle Until Date
    const untilVal = document.getElementById("recurrence_until").value;
    if (untilVal) {
      // Create date at end of day to be inclusive
      const untilDate = new Date(untilVal);
      untilDate.setHours(23, 59, 59);
      rruleOptions.until = untilDate;
    }

    // Handle Weekly Days
    if (freq === "WEEKLY") {
      const days = [];
      const dayMap = {
        SU: RRule.SU,
        MO: RRule.MO,
        TU: RRule.TU,
        WE: RRule.WE,
        TH: RRule.TH,
        FR: RRule.FR,
        SA: RRule.SA,
      };

      document.querySelectorAll(".dayCheckbox:checked").forEach((cb) => {
        if (dayMap[cb.value]) days.push(dayMap[cb.value]);
      });

      // Validation: If Weekly is selected, at least one day must be checked
      if (days.length === 0) {
        e.preventDefault();
        document.getElementById("day_freq_error").classList.remove("d-none");
        return false;
      } else {
        document.getElementById("day_freq_error").classList.add("d-none");
        rruleOptions.byweekday = days;
      }
    }

    // Generate the string (e.g., "FREQ=WEEKLY;BYDAY=MO,TU")
    ruleField.value = new RRule(rruleOptions).toString();
  } else {
    ruleField.value = ""; // Clear rule if "Does not repeat"
  }

  // --- 2. TIME CONVERSION LOGIC ---
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");
  const utcStart = document.getElementById("utc_start_time");
  const utcEnd = document.getElementById("utc_end_time");

  let startDateObj, endDateObj;

  if (startField && startField.type === "date") {
    if (startField.value)
      startDateObj = new Date(startField.value + "T00:00:00");
  } else if (startField && startField.value) {
    startDateObj = new Date(startField.value);
  }

  if (endField && endField.type === "date") {
    if (endField.value) endDateObj = new Date(endField.value + "T23:59:59");
  } else if (endField && endField.value) {
    endDateObj = new Date(endField.value);
  }

  // Time validation check
  if (startDateObj && endDateObj && endDateObj < startDateObj) {
    e.preventDefault();
    document.getElementById("time_error").classList.remove("d-none");
    return false;
  }
  document.getElementById("time_error").classList.add("d-none");

  if (startDateObj) utcStart.value = startDateObj.toISOString();
  if (endDateObj) utcEnd.value = endDateObj.toISOString();

  // --- 3. UNAVAILABILITY LOGIC ---
  if (isUnavailability) {
    const selectedStaff = staffSelectInstance
      ? staffSelectInstance.getValue()
      : "";

    if (!selectedStaff) {
      e.preventDefault();
      errorDiv?.classList.remove("d-none");
      return false;
    }
    errorDiv?.classList.add("d-none");

    const titleField = document.getElementById("title");
    const descField = document.getElementById("description");

    if (utcStart) utcStart.name = "staff_unavailability[utc_start_time]";
    if (utcEnd) utcEnd.name = "staff_unavailability[utc_end_time]";

    // Rename the recurrence field for the Unavailability model
    if (ruleField) ruleField.name = "staff_unavailability[recurrence_rule]";

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
  clearFormValidation();

  const form = document.getElementById("eventForm");
  if (!form) return;

  form.reset();
  initStaffSelect(true);

  const collapseEl = document.getElementById("event_mode_content");
  if (collapseEl) collapseEl.classList.add("show");

  setModalCategory("event");
  setCategorySelectorVisible(true);

  if (originalFormAction) {
    form.action = originalFormAction;
  }

  form.querySelector('input[name="_method"]')?.remove();

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

  document.getElementById("all_day_checkbox").checked = false;
  document.getElementById("start_time_field").type = "datetime-local";
  document.getElementById("end_time_field").type = "datetime-local";
  document.getElementById("end_time_field").disabled = false;
  document.getElementById("training-fields").style.display = "none";

  document.getElementById("eventModalLabel").textContent = "Add Event";
  const saveButton = document.getElementById("save_button");
  if (saveButton) {
    saveButton.value = "Save Draft";
    saveButton.classList.remove("btn-info");
    saveButton.classList.add("btn-success");
  }

  document.getElementById("modal_buttons").style.display = "flex";
  document.getElementById("publish_and_delete_forms").style.display = "none";
  document.getElementById("update_dropdown").style.display = "none";
}

// ============================================================
// FULL CALENDAR CALLBACKS
// ============================================================

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

export function eventCreate(info) {
  resetModalForm();
  const startField = document.getElementById("start_time_field");
  const endField = document.getElementById("end_time_field");
  const allDayCheckbox = document.getElementById("all_day_checkbox");

  if (info.allDay) {
    allDayCheckbox.checked = true;
    startField.type = "date";
    endField.type = "date";
    startField.value = info.startStr;
    const endDate = new Date(info.endStr);
    endDate.setDate(endDate.getDate() - 1);
    const pad = (n) => (n < 10 ? "0" + n : n);
    endField.value = `${endDate.getFullYear()}-${pad(endDate.getMonth() + 1)}-${pad(endDate.getDate())}`;
  } else {
    allDayCheckbox.checked = false;
    startField.type = "datetime-local";
    endField.type = "datetime-local";
    startField.value = formatCalendarDateForInput(info.startStr);
    endField.value = formatCalendarDateForInput(info.endStr);
  }

  document.getElementById("training-fields").style.display = "none";
  document.getElementById("addEventButton").click();
  addEventClick();
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
  const allDayCheckbox = document.getElementById("all_day_checkbox");

  if (eventImpl.allDay) {
    allDayCheckbox.checked = true;
    startTimeField.type = "date";
    endTimeField.type = "date";
    startTimeField.value = eventImpl.startStr;

    if (eventImpl.endStr) {
      const endDate = new Date(eventImpl.endStr);
      endDate.setDate(endDate.getDate() - 1);
      const pad = (n) => (n < 10 ? "0" + n : n);
      endTimeField.value = `${endDate.getFullYear()}-${pad(endDate.getMonth() + 1)}-${pad(endDate.getDate())}`;
    } else {
      endTimeField.value = eventImpl.startStr;
    }
    endTimeField.disabled = false;
  } else {
    allDayCheckbox.checked = false;
    startTimeField.type = "datetime-local";
    endTimeField.type = "datetime-local";
    startTimeField.value = formatCalendarDateForInput(eventImpl.startStr);
    endTimeField.value = formatCalendarDateForInput(eventImpl.endStr);
    endTimeField.disabled = false;
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
    trainingFields.style.display = "block";
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
    e.value = eventImpl.startStr;
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
  const allDayCheckbox = document.getElementById("all_day_checkbox");

  if (eventImpl.allDay) {
    allDayCheckbox.checked = true;
    startTimeField.type = "date";
    endTimeField.type = "date";
    startTimeField.value = eventImpl.startStr;
    if (eventImpl.endStr) {
      const endDate = new Date(eventImpl.endStr);
      endDate.setDate(endDate.getDate() - 1);
      const pad = (n) => (n < 10 ? "0" + n : n);
      endTimeField.value = `${endDate.getFullYear()}-${pad(endDate.getMonth() + 1)}-${pad(endDate.getDate())}`;
    } else {
      endTimeField.value = eventImpl.startStr;
    }
    endTimeField.disabled = false;
  } else {
    allDayCheckbox.checked = false;
    startTimeField.type = "datetime-local";
    endTimeField.type = "datetime-local";
    startTimeField.value = formatCalendarDateForInput(eventImpl.startStr);
    endTimeField.value = formatCalendarDateForInput(eventImpl.endStr);
    endTimeField.disabled = false;
  }

  document.getElementById("title").value = event.title || "Unavailable";
  document.getElementById("description").value =
    extendedProps.description || "";

  if (staffSelectInstance && extendedProps.userId) {
    staffSelectInstance.clear();
    staffSelectInstance.addItem(extendedProps.userId);
  }

  // Reuse recurrence logic
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
    e.value = eventImpl.startStr;
  });

  singleForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;
  followingForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;
  allForm.action = `/admin/staff_unavailabilities/${id}/delete_with_scope`;

  const modal = new Modal(document.getElementById("eventModal"));
  modal.show();
}
