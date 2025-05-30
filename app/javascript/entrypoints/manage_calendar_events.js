import { Collapse } from "bootstrap";
import { RRule } from "rrule";
import TomSelect from "tom-select";

import {
  parseLocalDatetimeString,
  toLocalDatetimeString,
} from "./calendar_helper";

document.addEventListener("turbo:load", async () => {
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

  // Staff select
  const staffSelect = document.getElementById("staff_select");
  let tomSelect;

  const fetchedStaffUnavailabilitiesRes = await fetch(
    "/admin/calendar/unavailabilities_json/" +
      document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const fetchedStaffUnavailabilities =
    await fetchedStaffUnavailabilitiesRes.json();

  // ---------------------------------------
  // Helper functions
  // ---------------------------------------
  function validateTimeRange() {
    const startDate = parseLocalDatetimeString(startTimeField.value);
    const endDate = parseLocalDatetimeString(endTimeField.value);

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

  function buildRule() {
    const startDate = parseLocalDatetimeString(startTimeField.value);
    const untilDate = new Date(untilInput.value + "T23:59:59");

    if (frequency.value === "") return (ruleField.value = "");

    const rule = new RRule({
      freq: RRule[frequency.value] || RRule.DAILY,
      dtstart: startDate,
      until: untilInput.value ? untilDate : null,
      byweekday: dayCheckboxes
        .filter((cb) => cb.checked)
        .map((cb) => RRule[cb.value]),
    });

    ruleField.value = rule.toString();
  }

  function handleDateIfAllDay() {
    const startDate =
      parseLocalDatetimeString(startTimeField.value) || new Date();
    startDate.setHours(0, 0, 0, 0);

    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + 1);

    startTimeField.value = toLocalDatetimeString(startDate);
    endTimeField.value = toLocalDatetimeString(endDate);
    endTimeField.disabled = true;

    const freq = frequency.value;
    if (freq === "WEEKLY") {
      const dayIndex = startDate.getDay();
      dayCheckboxes.forEach((checkbox, index) => {
        checkbox.checked = index === dayIndex;
      });
    }
  }

  function isUnavailableDuring(unavailabilities) {
    return unavailabilities.some((unavail) => {
      const start = new Date(unavail.start_date);
      const end = new Date(unavail.end_date);

      const eventStart = parseLocalDatetimeString(startTimeField.value);
      const eventEnd = parseLocalDatetimeString(endTimeField.value);

      // Recurring rule check
      if (unavail.recurrence_rule) {
        try {
          const rule = RRule.fromString(unavail.recurrence_rule);
          const occurrences = rule.between(eventStart, eventEnd, false);

          return occurrences.length > 0;
        } catch (e) {
          console.warn("Invalid RRULE:", e);
          return false;
        }
      }

      // One-time event overlap check
      return start < eventEnd && end > eventStart;
    });
  }

  function refreshTomSelect() {
    createTomSelectOptions();

    if (tomSelect) {
      tomSelect.sync();
      tomSelect.clearOptions();
      tomSelect.addOption(
        Array.from(staffSelect.options).map((option) => ({
          value: option.value,
          text: option.textContent,
          color: option.dataset.color,
          unavailable: option.dataset.unavailable,
        })),
      );
    } else {
      initTomSelect();
    }
  }

  function createTomSelectOptions() {
    const previouslySelected = Array.from(staffSelect.selectedOptions).map(
      (option) => option.value,
    );

    // Clear existing options
    staffSelect.innerHTML = "";

    if (
      !fetchedStaffUnavailabilities ||
      fetchedStaffUnavailabilities.length === 0
    ) {
      staffSelect.innerHTML = '<option value="">No staff available</option>';
      return;
    }

    const sortedStaff = fetchedStaffUnavailabilities.sort((a, b) => {
      const aUnavailable = isUnavailableDuring(a.unavailabilities);
      const bUnavailable = isUnavailableDuring(b.unavailabilities);

      if (aUnavailable !== bUnavailable) {
        return aUnavailable - bUnavailable;
      }
      return a.name.localeCompare(b.name);
    });

    sortedStaff.forEach((staff) => {
      const unavailable = isUnavailableDuring(staff.unavailabilities);
      const option = document.createElement("option");
      option.value = staff.id;
      option.textContent = staff.name;
      option.dataset.color = staff.color;
      option.dataset.unavailable = unavailable ? "true" : "false";
      option.selected = previouslySelected.includes(staff.id.toString());
      staffSelect.add(option);
    });
  }

  function initTomSelect() {
    if (tomSelect) {
      tomSelect.destroy();
    }

    // console.log("Initializing TomSelect with staff select:", staffSelect);

    tomSelect = new TomSelect(staffSelect, {
      plugins: ["remove_button", "restore_on_backspace"],
      render: {
        option: (data, escape) => {
          const color = escape(data.color || "#000");
          const unavailable = data.unavailable === "true";
          return `<div style="color: ${color}">
                        ${escape(data.text)} 
                        ${unavailable ? "<span style='color:red;'> (Unavailable)</span>" : ""}
                    </div>`;
        },
      },
      onItemAdd: function () {
        this.setTextboxValue("");
      },
      valueField: "value",
      labelField: "text",
      searchField: ["text"],
      create: false,
    });

    tomSelect.on("change", () => {
      const title = document.getElementById("title");

      if (title.value && title.value.trim() !== "") {
        const allStaffNames = fetchedStaffUnavailabilities.map(
          (staff) => staff.name,
        );

        const eventType = document.getElementById("event_type_select").value;

        if (isTitleAutogenerated(title.value, eventType, allStaffNames)) {
          title.value = "";
        }
      }
    });
  }

  function isTitleAutogenerated(title, eventType, allStaffNames) {
    if (!title || !eventType || allStaffNames.length === 0) return false;

    eventType = eventType.charAt(0).toUpperCase() + eventType.slice(1);

    // Escape all names for regex and sort longer names first
    const escapedNames = allStaffNames
      .map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
      .sort((a, b) => b.length - a.length); // prevents partial matches

    // Match exactly: "Name1(, Name2)*", composed only of allowed names
    const nameGroupPattern = `(?:${escapedNames.join("|")})(?:, (?:${escapedNames.join("|")}))*`;

    // Match full autogenerated pattern
    const fullPattern = `^${eventType} for ${nameGroupPattern}$`;
    const regex = new RegExp(fullPattern);

    return regex.test(title);
  }

  // ---------------------------------------
  // Event listeners
  // ---------------------------------------
  allDayCheckbox.addEventListener("change", () => {
    if (allDayCheckbox.checked) {
      handleDateIfAllDay();
    } else {
      endTimeField.disabled = false;
      const startDate = parseLocalDatetimeString(startTimeField.value);
      const endDate = new Date(startDate);
      endDate.setHours(endDate.getHours() + 1);
      endTimeField.value = toLocalDatetimeString(endDate);
    }
    validateTimeRange();
  });

  // Auto-set end time when start time changes
  startTimeField.addEventListener("change", () => {
    if (allDayCheckbox.checked) {
      handleDateIfAllDay();
    }
    validateTimeRange();
    refreshTomSelect();
  });

  // Validate when end time changes manually
  endTimeField.addEventListener("change", () => {
    validateTimeRange();
    refreshTomSelect();
  });

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
      const startDate = parseLocalDatetimeString(startTimeField.value);
      const dayIndex = startDate.getDay();
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
  const modal = document.getElementById("eventModal");
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
    const form = modal.querySelector("#eventModal form");
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
    // Reset TomSelect
    tomSelect?.destroy();
    tomSelect = null;
  });
  // Set values on modal open
  modal.addEventListener("show.bs.modal", (e) => {
    if (!startTimeField.value) {
      const now = new Date();
      const roundedNow = new Date(now);
      roundedNow.setMinutes(0, 0, 0);
      roundedNow.setHours(roundedNow.getHours() + 1);

      startTimeField.value = toLocalDatetimeString(roundedNow);
      endTimeField.value = toLocalDatetimeString(
        new Date(roundedNow.getTime() + 60 * 60 * 1000),
      );
    }

    validateTimeRange();
    createTomSelectOptions();
    initTomSelect();
  });

  // Before form submission, convert to UTC
  document.getElementById("eventForm").addEventListener("submit", (e) => {
    buildRule();

    const startLocal = parseLocalDatetimeString(startTimeField.value);
    const endLocal = parseLocalDatetimeString(endTimeField.value);

    const utcStartField = document.getElementById("utc_start_time");
    utcStartField.value = startLocal.toISOString();

    const utcEndField = document.getElementById("utc_end_time");
    utcEndField.value = endLocal.toISOString();

    tomSelect.sync();
  });
});
