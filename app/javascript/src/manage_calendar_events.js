import { Collapse } from "bootstrap";
import { RRule } from "rrule";
import TomSelect from "tom-select";
import { tomSelectOptions } from "./page_locale.js";

import { isHexColour } from "./calendar_background";
import { timesShown } from "./calendar_helper";
import { onPageLoad } from "./on_page";
import {
  fieldValue,
  instantToWall,
  startOfDay,
  storedRule,
  wallFromString,
  wallOfField,
  wallToInstant,
} from "./recurrence";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

function showStaffLoadError() {
  document.getElementById("staff_load_error").classList.remove("d-none");
}

function addEventButton() {
  return /** @type {HTMLButtonElement} */ (
    document.getElementById("addEventButton")
  );
}

// "Not ready" is the state at every start, including a page Turbo restored
// from its cache: the modal is closed to every entry point until the
// handlers below are attached again.
function resetReadyState() {
  document.getElementById("eventModal").removeAttribute("data-ready");
  addEventButton().disabled = true;
  document.getElementById("staff_load_error").classList.add("d-none");
}

document.addEventListener("turbo:before-cache", () => {
  if (document.getElementById("eventModal")) resetReadyState();
});

onPageLoad("#eventModal", () => {
  resetReadyState();

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

  // Staff select: the space's staff as the page lists them, then ranked by
  // the server for the event in the form (rankStaff).
  const staffSelect = document.getElementById("staff_select");
  const staffList = JSON.parse(staffSelect.dataset.staff || "[]");
  let rankedStaff = staffList;
  let rankings = 0;
  let tomSelect;

  // ---------------------------------------
  // Helper functions
  // ---------------------------------------
  // The form fields hold Toronto wall-clock times, like the calendar.
  function validateTimeRange() {
    const valid =
      wallOfField(endTimeField.value) > wallOfField(startTimeField.value);
    timeError.classList.toggle("d-none", valid);
    saveButton.disabled = !valid;
    saveButton.classList.toggle("disabled", !valid);
  }

  // The rule as it is stored: the start in Toronto time, the end a UTC stamp.
  function buildRule() {
    if (frequency.value === "") {
      ruleField.value = "";
      refreshTomSelect();
      return;
    }

    ruleField.value = storedRule(
      {
        freq: RRule[frequency.value] || RRule.DAILY,
        byweekday: dayCheckboxes
          .filter((cb) => cb.checked)
          .map((cb) => RRule[cb.value]),
      },
      wallOfField(startTimeField.value),
      untilInput.value,
    );
    refreshTomSelect();
  }

  function handleDateIfAllDay() {
    const startDate = startOfDay(wallOfField(startTimeField.value));

    startTimeField.value = fieldValue(startDate);
    endTimeField.value = fieldValue(startDate + DAY_MS);
    endTimeField.disabled = true;

    const freq = frequency.value;
    if (freq === "WEEKLY") {
      const dayIndex = new Date(startDate).getUTCDay();
      dayCheckboxes.forEach((checkbox, index) => {
        checkbox.checked = index === dayIndex;
      });
    }
  }

  const instantOfField = (field) =>
    new Date(wallToInstant(wallFromString(field.value))).toISOString();

  // Asks the server which staff are unavailable for the event in the form
  // (its occurrences over four weeks) and redraws the list with the answer;
  // only the latest answer is drawn. Without one the list stays as it was
  // and the admin is told.
  async function rankStaff() {
    const ranking = ++rankings;
    delete staffSelect.dataset.ranked;
    const query = new URLSearchParams({
      space_id: document.getElementById("space_id").value,
      start: instantOfField(startTimeField),
      end: instantOfField(endTimeField),
      recurrence_rule: ruleField.value,
    });
    try {
      const response = await fetch(`/admin/calendar/staff_conflicts?${query}`, {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) throw new Error(`staff ranking ${response.status}`);
      const ranked = await response.json();
      if (ranking !== rankings) return;
      rankedStaff = ranked;
      document.getElementById("staff_load_error").classList.add("d-none");
      redrawStaff();
      staffSelect.dataset.ranked = "true"; // the list shows the latest answer
    } catch (error) {
      console.error(error);
      if (ranking !== rankings) return;
      // the list must not keep the labels of an earlier answer
      rankedStaff = staffList;
      redrawStaff();
      showStaffLoadError();
    }
  }

  // An event that ends before it starts has nothing to rank.
  function rankWhenTimed() {
    if (wallOfField(endTimeField.value) > wallOfField(startTimeField.value)) {
      rankStaff();
    }
  }

  function refreshTomSelect() {
    redrawStaff();
    rankWhenTimed();
  }

  function redrawStaff() {
    createTomSelectOptions();

    if (tomSelect) {
      tomSelect.sync();
      tomSelect.clearOptions();
      tomSelect.addOption(
        Array.from(staffSelect.options).map((option) => ({
          value: option.value,
          text: option.textContent,
          color: option.dataset.color,
          unavailableDates: option.dataset.unavailableDates,
        })),
      );
      // an answer can arrive while the list is open: draw it again
      tomSelect.refreshOptions(false);
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

    if (rankedStaff.length === 0) {
      staffSelect.innerHTML = '<option value="">No staff yet</option>';
      return;
    }

    // available staff first, each part by name (the server's order)
    rankedStaff.forEach((staff) => {
      const option = document.createElement("option");
      option.value = staff.id;
      option.textContent = staff.name;
      option.dataset.color = staff.color;
      option.dataset.unavailableDates = staff.unavailableStarts.toString();
      option.selected = previouslySelected.includes(staff.id.toString());
      staffSelect.add(option);
    });
  }

  function initTomSelect() {
    if (tomSelect) {
      tomSelect.destroy();
    }

    tomSelect = new TomSelect(
      staffSelect,
      tomSelectOptions(staffSelect, {
        plugins: ["remove_button", "restore_on_backspace"],
        render: {
          option: (data, escape) => {
            const color = isHexColour(data.color) ? data.color : "#000";
            const unavailableDates = (data.unavailableDates || "")
              .split(",")
              .filter(Boolean);
            const firstDate = unavailableDates[0]
              ? new Date(unavailableDates[0]).toLocaleDateString(undefined, {
                  timeZone: "America/Toronto",
                })
              : null;
            const moreDates =
              unavailableDates.length > 1
                ? `+${unavailableDates.length - 1}`
                : "";

            return `<div style="color: ${color}">
                    ${escape(data.text)} 
                    ${firstDate ? `<span style='color:red;'> (Unavailable ${firstDate}${moreDates})</span>` : ""}
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
      }),
    );
  }

  function isTitleAutogenerated(title, allStaffNames) {
    if (allStaffNames.length === 0) return false;

    // Escape and sort names to avoid partial matches
    const escapedNames = allStaffNames
      .map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
      .sort((a, b) => b.length - a.length);

    const namesPattern = `(?:${escapedNames.join("|")})`;
    const nameGroupPattern = `${namesPattern}(?:, ${namesPattern})*`;

    const fullPattern = `\\sfor\\s${nameGroupPattern}$`;

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
      const start = wallToInstant(wallOfField(startTimeField.value));
      endTimeField.value = fieldValue(instantToWall(start + HOUR_MS));
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
      const dayIndex = new Date(wallOfField(startTimeField.value)).getUTCDay();
      if (dayCheckboxes[dayIndex]) dayCheckboxes[dayIndex].checked = true;
    }
    buildRule(); // ranks the staff for the new repeat
  });

  // Manage when the until date or checkboxes change
  [untilInput, ...dayCheckboxes].forEach((el) => {
    el.addEventListener("change", () => {
      const noDay = dayCheckboxes.every((checkbox) => !checkbox.checked);
      dayFreqError.classList.toggle("d-none", !noDay);
      buildRule(); // ranks the staff for the new repeat
    });
  });

  // "Update" radio buttons
  radios.forEach((radio) => {
    radio.addEventListener("click", (e) => {
      e.stopPropagation(); // Stop the dropdown from closing
    });
  });

  // Handle training options
  const eventTypeSelect = document.getElementById("event_type_select");
  const trainingFields = document.getElementById("training-fields");
  eventTypeSelect.addEventListener("change", () => {
    trainingFields.style.display =
      eventTypeSelect.value === "training" ? "" : "none";
  });

  // Confirm before modal exit
  const modal = document.getElementById("eventModal");
  modal.addEventListener("hide.bs.modal", (e) => {
    if (!modal.dataset.saved && !confirm(modal.dataset.exitMessage)) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }
    delete modal.dataset.shown;
  });
  // Ready signal: set once the open transition has finished, since a modal
  // still fading in ignores a close request
  modal.addEventListener("shown.bs.modal", () => {
    modal.dataset.shown = "true";
  });
  // Reset the form
  modal.addEventListener("hidden.bs.modal", () => {
    modal.querySelector("form").reset();
    modal.querySelector("#calendar_dialog_alert").replaceChildren();
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
      const now = wallOfField("");
      const nextHour = now - (now % HOUR_MS) + HOUR_MS;

      startTimeField.value = fieldValue(nextHour);
      endTimeField.value = fieldValue(nextHour + HOUR_MS);
    }

    validateTimeRange();
    createTomSelectOptions();
    initTomSelect();
    rankWhenTimed();
  });

  // Before form submission, send the instants of the Toronto times
  document.getElementById("eventForm").addEventListener("submit", (e) => {
    buildRule();
    const keepTimes = document.getElementById("keep_series_times");
    // sent ("1") only while the times are as the dialog filled them
    keepTimes.disabled = keepTimes.dataset.filled !== timesShown();

    document.getElementById("utc_start_time").value = new Date(
      wallToInstant(wallOfField(startTimeField.value)),
    ).toISOString();
    document.getElementById("utc_end_time").value = new Date(
      wallToInstant(wallOfField(endTimeField.value)),
    ).toISOString();

    tomSelect.sync();

    // Autogenerate title if not customized
    const title = document.getElementById("title");
    if (title.value.trim()) {
      const allStaffNames = staffList.map((staff) => staff.name);
      if (isTitleAutogenerated(title.value, allStaffNames)) title.value = "";
    }
  });

  // Every modal handler above is attached: the page may now open the modal.
  modal.dataset.ready = "true";
  addEventButton().disabled = false;
});
