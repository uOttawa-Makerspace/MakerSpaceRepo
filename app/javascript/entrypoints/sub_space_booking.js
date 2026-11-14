import interactionPlugin from "@fullcalendar/interaction";
import listPlugin from "@fullcalendar/list";
import TomSelect from "tom-select";
import "flatpickr";
import { flatpickrOptions, tomSelectOptions } from "../src/page_locale.js";
import { Toast } from "bootstrap";
import { csrfHeaders } from "../src/csrf";
import { calendarTexts, pageCalendar } from "../src/page_calendar.js";
import {
  failureText,
  parseBody,
  requestJson,
  requestResult,
  resultError,
  serverError,
} from "../src/request_error";

// ─── Small helpers ────────────────────────────────────────────────────────────

// The admin user picker. The server does the matching (name or username, at least `minLength`
// characters), and the list always obeys one rule: it holds only the server's answer for exactly the text
// now in the box, and nothing when that text is shorter than the minimum.
//  - an answer is accepted only if its query is still the text in the box, and the response is OK;
//  - whenever the text differs from the answered query (typing, or Tom Select itself emptying the box on
//    selection, close or clear) the options are dropped before anything is shown.
// `score` always 1 keeps Tom Select from filtering the server's matches again by name.
function userPicker(select) {
  const minLength = Number(select.dataset.minLength);
  const hint = select.dataset.hint;
  let answeredQuery = null;

  const picker = new TomSelect(
    select,
    tomSelectOptions(select, {
      plugins: ["remove_button"],
      valueField: "id",
      labelField: "name",
      searchField: ["name"],
      options: [],
      score: () => () => 1,
      shouldLoad: (query) => query.length >= minLength,
      render: {
        not_loading: () => {
          const el = document.createElement("div");
          el.className = "no-results";
          el.textContent = hint;
          return el;
        },
      },
      /** @this {import("tom-select").default} */
      load(query, callback) {
        // an unanswered lookup is forgotten, so typing the same text again asks the server again
        const skip = () => {
          delete this.loadedSearches[query];
          callback();
        };
        const answer = (people) => {
          if (!people || this.inputValue() !== query) return skip();
          answeredQuery = query;
          callback(people);
        };
        if (this.inputValue() !== query) return skip();
        fetch(`/sub_space_booking/users?query=${encodeURIComponent(query)}`)
          .then((r) => (r.ok ? r.json() : null))
          .then(answer, skip);
      },
    }),
  );

  const dropStaleOptions = () => {
    if (answeredQuery === null || answeredQuery === picker.inputValue()) return;
    answeredQuery = null;
    picker.clearOptions();
    picker.refreshOptions(false);
  };
  picker.hook("before", "refreshOptions", dropStaleOptions);
  picker.hook("after", "onInput", dropStaleOptions);
  picker.hook("after", "setTextboxValue", dropStaleOptions);
  return picker;
}

// The booking's date and time pickers, which show the date and time worded in
// the page's language. flatpickrOptions copies these, so every picker shares them.
const DATE_TIME_PICKER = { enableTime: true, time_24hr: true, altInput: true };

// ── Recurring-approval modal: one checked box per date when it opens ────────
// One row of the modal: a checked box for the booking and the date as its label, in plain text.
function recurringDateRow([id, label]) {
  const row = document.createElement("div");
  row.className = "form-check p-2 border rounded";
  const box = document.createElement("input");
  box.className = "form-check-input";
  box.type = "checkbox";
  box.name = "sub_space_booking_ids[]";
  box.value = id;
  box.id = `rc_${id}`;
  box.defaultChecked = true;
  const text = document.createElement("label");
  text.className = "form-check-label w-100";
  text.htmlFor = box.id;
  text.textContent = label;
  row.append(box, text);
  return row;
}

function wireRecurringApproval() {
  const approveRecurringModal = document.getElementById(
    "approveRecurringModal",
  );
  if (!approveRecurringModal) return;
  approveRecurringModal.addEventListener("show.bs.modal", (e) => {
    const dates = JSON.parse(e.relatedTarget.dataset.dates);
    document
      .getElementById("recurring-checkboxes")
      .replaceChildren(...dates.map(recurringDateRow));
  });

  const checkAll = (checked) => () =>
    approveRecurringModal
      .querySelectorAll('input[type="checkbox"]')
      .forEach((c) => (c.checked = checked));
  document
    .getElementById("recurringSelectAll")
    ?.addEventListener("click", checkAll(true));
  document
    .getElementById("recurringSelectNone")
    ?.addEventListener("click", checkAll(false));
}

// A select-all box ticks or clears every row checkbox.
function wireSelectAll(boxId, rowSelector) {
  document.getElementById(boxId)?.addEventListener("change", (e) => {
    document.querySelectorAll(rowSelector).forEach((c) => {
      c.checked = e.currentTarget.checked;
    });
  });
}

// The admin lists, the access-request form and the admin "grant access" user search.
function wireAdminLists() {
  wireRecurringApproval();
  wireSelectAll("pending_bookings_select_all", ".pending-booking-select");
  wireSelectAll("userRequestSelectAll", ".user-request-select");

  const supervisorsContainer = document.getElementById("supervisor-select");
  document.querySelectorAll(".identity-button").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      if (supervisorsContainer)
        supervisorsContainer.style.display =
          e.target.value === "Staff" ? "block" : "none";
    });
  });

  const userSelect = document.getElementById("user_booking_select");
  if (userSelect && !userSelect.tomSelect) {
    userSelect.tomSelect = userPicker(userSelect);
  }
}

// ─── turbo:load — runs every soft navigation ──────────────────────────────────

document.addEventListener("turbo:load", function () {
  wireAdminLists();

  // ── Edit-page flatpickr ───────────────────────────────────────────────────
  document
    .getElementById("sub_space_booking_start_time")
    ?.flatpickr(flatpickrOptions(document, DATE_TIME_PICKER, "date_time"));
  document
    .getElementById("sub_space_booking_end_time")
    ?.flatpickr(flatpickrOptions(document, DATE_TIME_PICKER, "date_time"));

  // ── Calendar setup (only on the calendar tab) ─────────────────────────────
  const bookedCalendarEl = document.getElementById("booked-calendar");
  if (bookedCalendarEl) setUpBookingCalendar(bookedCalendarEl);
}); // end turbo:load

// ─── The booking calendar and its modal, built again on every visit ───────────

function setUpBookingCalendar(bookedCalendarEl) {
  let start_picker, end_picker, recurring_picker;

  // ---- Modal helpers -------------------------------------------------------
  function openModal() {
    const m = document.getElementById("bookModal");
    if (!m) return;
    m.style.display = "block";
    m.classList.add("show");
    // Backdrop
    if (!document.getElementById("book-modal-backdrop")) {
      const bd = document.createElement("div");
      bd.id = "book-modal-backdrop";
      bd.className = "modal-backdrop fade show";
      document.body.appendChild(bd);
    }
  }

  function closeModal() {
    const modal = document.getElementById("bookModal");
    if (!modal) return;
    modal.style.display = "none";
    modal.classList.remove("show");
    document.getElementById("book-modal-backdrop")?.remove();

    document.getElementById("book-name").value = "";
    document.getElementById("book-description").value = "";
    recurring_picker?.setDate(null);

    document.getElementById("bookSave").removeAttribute("disabled");
    document.getElementById("bookUpdate").removeAttribute("disabled");

    modal
      .querySelectorAll(".is-invalid")
      .forEach((el) => el.classList.remove("is-invalid"));
    modal
      .querySelectorAll(".invalid-feedback:not(#end-date-validation)")
      .forEach((el) => el.remove());
    document.getElementById("end-date-validation")?.classList.add("d-none");
  }

  function toggleRecurring() {
    const isRecurring = document.getElementById("book-recurring")?.checked;
    const ids = [
      "book-recurring-end",
      "book-recurring-end-label",
      "book-recurring-type",
      "book-recurring-type-label",
    ];
    ids.forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.style.display = isRecurring ? "block" : "none";
    });
    const fp = document.getElementsByClassName("flatpickr")[0];
    if (fp) fp.style.display = isRecurring ? "block" : "none";
  }

  // ---- Create (new booking) ------------------------------------------------
  function createEvent(arg) {
    document.getElementById("bookSave").style.display = "block";
    document.getElementById("bookUpdate").style.display = "none";
    document.getElementById("subspace").style.display = "none";
    document.getElementById("subspace_header").style.display = "none";
    document.getElementById("bookDelete").style.display = "none";
    document.getElementById("bookDeleteRecurringDropdown").style.display =
      "none";
    document.getElementById("bookingModalLabel").innerText = "New Booking";
    document.getElementById("book-recurring").style.display = "inline-block";
    document.getElementById("book-recurring-label").style.display =
      "inline-block";

    toggleRecurring();
    openModal();

    if (arg) {
      start_picker.setDate(Date.parse(arg.startStr));
      end_picker.setDate(Date.parse(arg.endStr));
    }
    document.getElementById("book-name")?.focus();
  }

  // The page's translated texts (data attributes of the toast).
  function bookingText(name) {
    return document.getElementById("booking_toast")?.dataset[name] ?? "";
  }

  // The booking lookup answers JSON only to staff; anything else (a refusal
  // redirected to an HTML page, a server error) is shown as the server's reason, not parsed.
  function fetchBooking(id) {
    return requestJson(
      `/sub_space_booking/get_sub_space_booking?id=${id}`,
      {
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
      },
      { fallback: bookingText("unavailable"), requireBody: true },
    );
  }

  function showBookingLoadError(error) {
    showToast(
      bookingText("unavailableTitle"),
      failureText(error, bookingText("unavailable")),
    );
  }

  // ---- Edit (existing booking) ---------------------------------------------
  function editEvent(arg) {
    if (!arg.event.extendedProps.viewable) return;
    document.getElementById("bookSave").style.display = "none";
    document.getElementById("bookUpdate").style.display = "block";
    document.getElementById("subspace").style.display = "block";
    document.getElementById("subspace_header").style.display = "block";
    document.getElementById("bookingModalLabel").innerText = "Update Booking";
    document.getElementById("sub_space_booking_id").value =
      arg.event.id.split("_")[1];
    document.getElementById("book-recurring").style.display = "none";
    document.getElementById("book-recurring-label").style.display = "none";

    fetchBooking(arg.event.id.split("_")[1])
      .then((data) => {
        document.getElementById("book-name").value = data.name;
        document.getElementById("book-description").value = data.description;
        start_picker.setDate(Date.parse(data.start_time.slice(0, -6)));
        end_picker.setDate(Date.parse(data.end_time.slice(0, -6)));
        document.getElementById("book-recurring").checked = false;

        const blockingEl = document.getElementById("book-blocking");
        if (blockingEl) blockingEl.checked = data.blocking;

        const isRecurring = data.recurring_booking_id != null;
        document.getElementById("bookDelete").style.display = isRecurring
          ? "none"
          : "block";
        document.getElementById("bookDeleteRecurringDropdown").style.display =
          isRecurring ? "block" : "none";

        document.getElementById("subspace").value = data.sub_space_id;
        toggleRecurring();
        openModal();
      })
      .catch(showBookingLoadError);
  }

  // ---- Flatpickr instances -------------------------------------------------
  start_picker = document
    .getElementById("book-start")
    .flatpickr(flatpickrOptions(document, DATE_TIME_PICKER, "date_time"));
  end_picker = document
    .getElementById("book-end")
    .flatpickr(flatpickrOptions(document, DATE_TIME_PICKER, "date_time"));
  recurring_picker = document
    .getElementById("book-recurring-end")
    .flatpickr(
      flatpickrOptions(document, { enableTime: false, altInput: true }, "date"),
    );

  // ---- Modal button wiring ------------------------------------------------
  document.getElementById("bookCancel").addEventListener("click", closeModal);
  document.getElementById("bookClose").addEventListener("click", closeModal);
  document.getElementById("bookSave").addEventListener("click", bookEvent);
  document.getElementById("bookUpdate").addEventListener("click", updateEvent);
  document
    .getElementById("bookDelete")
    .addEventListener("confirmation:confirmed", deleteEvent);
  document
    .getElementById("bookRecurringDeleteOne")
    .addEventListener("confirmation:confirmed", deleteEvent);
  document
    .getElementById("bookRecurringDeleteRest")
    .addEventListener("confirmation:confirmed", deleteRecurringEvent);
  document
    .getElementById("book-recurring")
    .addEventListener("change", toggleRecurring);

  // ---- Date validation helper ---------------------------------------------
  function validateDates() {
    if (
      start_picker.selectedDates.length > 0 &&
      end_picker.selectedDates.length > 0 &&
      start_picker.selectedDates[0] >= end_picker.selectedDates[0]
    ) {
      document.getElementById("end-date-validation").classList.remove("d-none");
      end_picker.altInput.classList.add("is-invalid");
      return false;
    }
    document.getElementById("end-date-validation").classList.add("d-none");
    end_picker.altInput.classList.remove("is-invalid");
    return true;
  }

  // ---- Save and delete requests ------------------------------------------
  // A JSON request with the CSRF token; a delete has no data, so no body.
  function jsonRequest(method, url, data) {
    return new Request(url, {
      method,
      headers: csrfHeaders({
        "Content-Type": "application/json",
        Accept: "application/json",
      }),
      body: JSON.stringify(data),
    });
  }

  function bookEvent(e) {
    if (!validateDates()) return;
    e.target.setAttribute("disabled", "");

    makeRequest(
      jsonRequest("POST", "/sub_space_booking", {
        sub_space_booking: {
          name: document.getElementById("book-name").value,
          description: document.getElementById("book-description").value,
          start_time: start_picker.input.value,
          end_time: end_picker.input.value,
          sub_space_id: new URLSearchParams(window.location.search).get("room"),
          recurring: document.getElementById("book-recurring").checked,
          recurring_end: recurring_picker.selectedDates[0],
          recurring_frequency: document.getElementById("book-recurring-type")
            .value,
          blocking: document.getElementById("book-blocking")?.checked ?? false,
        },
      }),
      e.target,
    );
  }

  function updateEvent() {
    if (!validateDates()) return;
    const btn = document.getElementById("bookUpdate");
    btn.setAttribute("disabled", "");

    const id = document.getElementById("sub_space_booking_id").value;
    makeRequest(
      jsonRequest("PATCH", `/sub_space_booking/${id}/update`, {
        sub_space_booking: {
          name: document.getElementById("book-name").value,
          description: document.getElementById("book-description").value,
          start_time: start_picker.input.value,
          end_time: end_picker.input.value,
          sub_space_id: document.getElementById("subspace").value,
          blocking: document.getElementById("book-blocking")?.checked ?? false,
        },
      }),
      btn,
      bookingText("updated"),
    );
  }

  function deleteEvent() {
    const id = document.getElementById("sub_space_booking_id").value;
    makeRequest(
      jsonRequest("DELETE", `/sub_space_booking/${id}/delete/${id}`),
      document.getElementById("bookDelete"),
    );
  }

  function deleteRecurringEvent() {
    const id = document.getElementById("sub_space_booking_id").value;
    makeRequest(
      jsonRequest(
        "DELETE",
        `/sub_space_booking/${id}/delete_remaining_recurring`,
      ),
      document.getElementById("bookRecurringDeleteRest"),
    );
  }

  // The toast is red for a problem and green for a success.
  function showToast(title, text, success = false) {
    const toastEl = document.getElementById("booking_toast");
    if (!toastEl) return;
    const tone = success ? ["success", "danger"] : ["danger", "success"];
    for (const el of [toastEl, toastEl.querySelector(".toast-header")]) {
      el?.classList.add(`text-bg-${tone[0]}`);
      el?.classList.remove(`text-bg-${tone[1]}`);
    }
    document.getElementById("toast_title").innerText = title;
    document.getElementById("toast_text").innerText = text;
    Toast.getOrCreateInstance(toastEl).show();
  }

  // ---- Shared fetch handler -----------------------------------------------
  // successText, when given, is shown as a success toast once the save worked.
  function makeRequest(request, triggerBtn, successText = "") {
    requestResult(request)
      .then((result) => {
        const parsed = parseBody(result.text);
        if (parsed?.errors) showErrors(parsed, triggerBtn);
        else if (result.ok) showSaved(parsed, successText);
        else showRefusal(result, triggerBtn);
      })
      .catch((error) => {
        triggerBtn?.removeAttribute("disabled");
        showToast(bookingText("failedTitle"), failureText(error));
      });
  }

  // A refusal with no per-field errors (a server error, a missing record): say why, and keep the form.
  function showRefusal(result, triggerBtn) {
    triggerBtn?.removeAttribute("disabled");
    showToast(bookingText("failedTitle"), resultError(result));
  }

  // Success: close the modal and reload the calendar data, or the whole page
  // when the answer was not JSON (a hard redirect).
  function showSaved(parsed, successText) {
    closeModal();
    bookedCalendar.refetchEvents();
    if (successText) showToast(bookingText("updatedTitle"), successText, true);
    if (parsed === null) window.location.reload();
  }

  // A partly booked recurring series (errors with booked > 0) has some
  // occurrences now, so show the calendar and say what happened rather than
  // reporting a plain failure (the user would rebook and create duplicates).
  function showErrors(parsed, triggerBtn) {
    if (parsed.booked > 0) {
      closeModal();
      bookedCalendar.refetchEvents();
      showToast("Booking partly done", parsed.summary);
      window.scrollTo(0, 0);
      return;
    }
    triggerBtn?.removeAttribute("disabled");
    for (const error of parsed.errors) showError(error);
  }

  // "<Type> <message>": a booking rule (duration, slot) is a toast that closes
  // the modal; anything else marks the field "book-<type>" once.
  function showError(error) {
    const [type, ...rest] = error.split(" ");
    const message = rest.join(" ");
    if (["DurationHour", "DurationWeek", "TimeSlot"].includes(type)) {
      showToast(bookingText("failedTitle"), message);
      closeModal();
      window.scrollTo(0, 0);
      return;
    }
    const field = document.getElementById("book-" + type.toLowerCase());
    if (!field || field.classList.contains("is-invalid")) return;
    const feedback = document.createElement("div");
    feedback.className = "invalid-feedback";
    feedback.innerText = message || error;
    field.classList.add("is-invalid");
    field.after(feedback);
  }

  // ---- FullCalendar -------------------------------------------------------
  // The calendar feed failed: show the server's reason when it sent one.
  async function showFeedError(error) {
    const body = await error?.response?.json?.().catch(() => null);
    showToast(
      bookingText("failedTitle"),
      serverError(body, bookingText("feed")),
    );
  }

  const bookText = calendarTexts(bookedCalendarEl).book;
  const calendarOptions = {
    initialDate: window.location.href.includes("start")
      ? new Date(new URLSearchParams(window.location.search).get("start"))
      : new Date(),
    height: "auto",
    headerToolbar: {
      left: "prev,today,next",
      center: "",
      right: "book,timeGridWeek",
    },
    customButtons: {
      book: { text: bookText, click: () => createEvent() },
    },
    views: {
      timeGridWeek: {
        dayHeaderFormat: { weekday: "short", day: "numeric", month: "short" },
      },
    },
    allDaySlot: false,
    initialView: "timeGridWeek",
    navLinks: true,
    slotEventOverlap: false,
    slotMinTime: "06:00:00",
    slotMaxTime: "22:00:00",
    selectable: true,
    eventTimeFormat: { hour: "2-digit", minute: "2-digit", hour12: false },
    dayMaxEvents: true,
    eventSources: [
      {
        id: "booked",
        url: `/sub_space_booking/bookings?room=${new URLSearchParams(
          window.location.search,
        ).get("room")}`,
        // Surface fetch errors in the console rather than silently failing
        failure: (error) => showFeedError(error),
      },
    ],
    select: (arg) => createEvent(arg),
    eventClick: (arg) => editEvent(arg),
  };
  const bookedCalendar = pageCalendar(
    bookedCalendarEl,
    calendarOptions,
    interactionPlugin,
    listPlugin,
  );

  bookedCalendar.render();
}

// ─── Tab routing (turbo:render + initial load) ────────────────────────────────

function makeActive(tab, param) {
  let tabContent = document.getElementById(tab);
  let tabButton = document.getElementById(tab + "-btn");
  let tabButtons = document.getElementsByClassName("nav-link");
  if (!(tabContent && tabButton && tabButtons)) {
    return;
  }
  [...tabButtons].forEach((button) => {
    button.classList.remove("active");
  });
  tabButton.classList.add("active");
  let tabContents = document.getElementsByClassName("tab-pane");
  [...tabContents].forEach((content) => {
    content.classList.remove("active");
    content.classList.remove("show");
  });
  tabContent.classList.add("active");
  tabContent.classList.add("show");

  if (param && tab === "booking-admin-tab") {
    let table = document.getElementById(param);
    // SAFETY CHECK: Prevents JS from crashing if the ID isn't found
    if (table) {
      table.scrollIntoView({
        behavior: "smooth",
        block: "start",
        inline: "nearest",
      });
      window.scrollBy(
        0,
        -7 * parseFloat(getComputedStyle(document.documentElement).fontSize),
      );
    }
  }
}

function ready() {
  const anchor = window.location.hash.replace("#", "");
  const params = new URLSearchParams(window.location.search);

  const paramToSection = {
    pending_page: "pendingBody",
    approved_page: "approvedBody",
    denied_page: "declinedBody",
    old_pending_page: "pastPendingBody",
    old_approved_page: "pastApprovedBody",
    old_denied_page: "pastDeclinedBody",
  };

  let scrollTarget = null;
  for (const [key, sectionId] of Object.entries(paramToSection)) {
    if (params.has(key)) {
      scrollTarget = sectionId;
      break;
    }
  }

  if (anchor) {
    makeActive(anchor, null);
  } else if (scrollTarget) {
    makeActive("booking-admin-tab", scrollTarget);
  } else {
    makeActive("booking-calendar-tab", null);
  }
}

// Wire up tab buttons (outside turbo:load so they survive re-renders)
document.querySelectorAll(".tab-link").forEach((btn) => {
  btn.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    // id is e.g. "booking-calendar-tab-btn" → target is "booking-calendar-tab"
    const target =
      btn.getAttribute("data-bs-target")?.replace("#", "") ??
      btn.id.replace("-btn", "");
    makeActive(target, null);
  });
});

document.addEventListener("turbo:render", ready);
ready();
