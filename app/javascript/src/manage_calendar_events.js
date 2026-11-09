import { Collapse } from "bootstrap";
import { RRule } from "rrule";
import TomSelect from "tom-select";

import { isHexColour } from "./calendar_background";
import { onPageLoad } from "./on_page";
import {
  entryIntervals,
  fieldValue,
  instantToWall,
  occurrencesOverlapping,
  startOfDay,
  startingAt,
  storedRule,
  wallFromString,
  wallOfField,
  wallToInstant,
} from "./recurrence";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const FOUR_WEEKS_MS = 28 * DAY_MS;

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

onPageLoad("#eventModal", async () => {
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

  // Staff select
  const staffSelect = document.getElementById("staff_select");
  let tomSelect;

  let fetchedStaffUnavailabilitiesRes = null;
  try {
    fetchedStaffUnavailabilitiesRes = await fetch(
      "/admin/calendar/unavailabilities_json/" +
        document.getElementById("space_id").value,
    );
  } catch (error) {
    console.error(error);
  }
  // Without the staff data the modal must not be used: tell the admin and
  // leave "Add Event" disabled.
  if (!fetchedStaffUnavailabilitiesRes?.ok) {
    showStaffLoadError();
    return;
  }
  const fetchedStaffUnavailabilities =
    await fetchedStaffUnavailabilitiesRes.json();

  // ---------------------------------------
  // Helper functions
  // ---------------------------------------
  // The form fields hold Toronto wall-clock times, like the calendar.
  function validateTimeRange() {
    const startDate = wallOfField(startTimeField.value);
    const endDate = wallOfField(endTimeField.value);

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

  // The event's own occurrences over the next four weeks (just itself when
  // it does not repeat), as wall times read from the form fields.
  function eventOccurrences() {
    const start = wallFromString(startTimeField.value);
    const end = wallFromString(endTimeField.value);
    if (!(end > start)) return [];
    if (!ruleField.value) return [{ start, end }];
    return occurrencesOverlapping(
      startingAt(ruleField.value, start),
      end - start,
      start,
      start + FOUR_WEEKS_MS,
    );
  }

  // Start times (instants) of the event occurrences that fall inside one of
  // the given unavailabilities. Each unavailability is expanded once over the
  // whole span of the event's occurrences.
  function isUnavailableDuring(occurrences, unavailabilities) {
    if (occurrences.length === 0) return [];
    const from = occurrences[0].start;
    const to = occurrences[occurrences.length - 1].end;
    const busy = unavailabilities.flatMap((entry) =>
      entryIntervals(entry, from, to),
    );
    return occurrences
      .filter((occurrence) =>
        busy.some(
          (slot) => slot.start < occurrence.end && slot.end > occurrence.start,
        ),
      )
      .map((occurrence) => new Date(wallToInstant(occurrence.start)));
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
          unavailableDates: option.dataset.unavailableDates,
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
      staffSelect.innerHTML = '<option value="">No staff yet</option>';
      return;
    }

    const occurrences = eventOccurrences();
    const staffWithAvailability = fetchedStaffUnavailabilities.map((staff) => {
      const unavailableDates = isUnavailableDuring(
        occurrences,
        staff.unavailabilities,
      );
      return { ...staff, unavailableDates };
    });

    const sortedStaff = staffWithAvailability.sort((a, b) => {
      const aUnavailable = a.unavailableDates.length > 0;
      const bUnavailable = b.unavailableDates.length > 0;

      if (aUnavailable !== bUnavailable) return aUnavailable - bUnavailable; // available first

      return a.name.localeCompare(b.name); // then sort by name
    });

    sortedStaff.forEach((staff) => {
      const option = document.createElement("option");
      option.value = staff.id;
      option.textContent = staff.name;
      option.dataset.color = staff.color;
      option.dataset.unavailableDates = staff.unavailableDates.toString();
      option.selected = previouslySelected.includes(staff.id.toString());
      staffSelect.add(option);
    });
  }

  function initTomSelect() {
    if (tomSelect) {
      tomSelect.destroy();
    }

    tomSelect = new TomSelect(staffSelect, {
      plugins: ["remove_button", "restore_on_backspace"],
      render: {
        option: (data, escape) => {
          const color = isHexColour(data.color) ? data.color : "#000";
          const unavailableDates = data.unavailableDates
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
    });

    tomSelect.on("focus", () => {
      buildRule();
    });
  }

  function isTitleAutogenerated(title, allStaffNames) {
    if (!title || allStaffNames.length === 0) return false;

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
      const now = wallOfField("");
      const nextHour = now - (now % HOUR_MS) + HOUR_MS;

      startTimeField.value = fieldValue(nextHour);
      endTimeField.value = fieldValue(nextHour + HOUR_MS);
    }

    validateTimeRange();
    createTomSelectOptions();
    initTomSelect();
  });

  // Before form submission, send the instants of the Toronto times
  document.getElementById("eventForm").addEventListener("submit", (e) => {
    buildRule();

    document.getElementById("utc_start_time").value = new Date(
      wallToInstant(wallOfField(startTimeField.value)),
    ).toISOString();
    document.getElementById("utc_end_time").value = new Date(
      wallToInstant(wallOfField(endTimeField.value)),
    ).toISOString();

    tomSelect.sync();

    // Autogenerate title if not customized
    const title = document.getElementById("title");
    if (title.value && title.value.trim() !== "") {
      const allStaffNames = fetchedStaffUnavailabilities.map(
        (staff) => staff.name,
      );
      if (isTitleAutogenerated(title.value, allStaffNames)) title.value = "";
    }
  });

  // Every modal handler above is attached: the page may now open the modal.
  modal.dataset.ready = "true";
  addEventButton().disabled = false;
});
