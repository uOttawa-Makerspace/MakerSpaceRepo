import { Calendar } from "@fullcalendar/core";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import TomSelect from "tom-select";
import "flatpickr";

// ─── Small helpers ────────────────────────────────────────────────────────────

function updateSelectedCount(checkboxClass, displayId) {
  const count = document.querySelectorAll(`${checkboxClass}:checked`).length;
  const el = document.getElementById(displayId);
  if (!el) return;
  el.textContent = count > 0 ? `${count} selected` : "";
}

// ─── turbo:load — runs every soft navigation ──────────────────────────────────

document.addEventListener("turbo:load", function () {
  // ── Recurring-approval modal ──────────────────────────────────────────────
  const approveRecurringModal = document.getElementById(
    "approveRecurringModal",
  );
  if (approveRecurringModal) {
    // Populate checkboxes when the modal opens
    approveRecurringModal.addEventListener("show.bs.modal", (e) => {
      const dates = JSON.parse(e.relatedTarget.dataset.dates);
      const container = document.getElementById("recurring-checkboxes");
      container.innerHTML = "";
      dates.forEach(([id, label]) => {
        const div = document.createElement("div");
        div.className = "form-check p-2 border rounded";
        div.innerHTML = `
          <input class="form-check-input" type="checkbox"
                 name="sub_space_booking_ids[]"
                 value="${id}"
                 id="rc_${id}"
                 checked />
          <label class="form-check-label w-100" for="rc_${id}">${label}</label>
        `;
        container.appendChild(div);
      });
    });

    document
      .getElementById("recurringSelectAll")
      ?.addEventListener("click", () => {
        approveRecurringModal
          .querySelectorAll('input[type="checkbox"]')
          .forEach((c) => (c.checked = true));
      });
    document
      .getElementById("recurringSelectNone")
      ?.addEventListener("click", () => {
        approveRecurringModal
          .querySelectorAll('input[type="checkbox"]')
          .forEach((c) => (c.checked = false));
      });
  }

  // ── Pending bookings select-all ───────────────────────────────────────────
  const pendingSelectAll = document.getElementById(
    "pending_bookings_select_all",
  );
  if (pendingSelectAll) {
    // Attach per-checkbox change listeners for the live count
    document.querySelectorAll(".pending-booking-select").forEach((c) => {
      c.addEventListener("change", () =>
        updateSelectedCount(
          ".pending-booking-select",
          "pending-selected-count",
        ),
      );
    });
    pendingSelectAll.addEventListener("change", (e) => {
      document.querySelectorAll(".pending-booking-select").forEach((c) => {
        c.checked = e.currentTarget.checked;
      });
      updateSelectedCount(".pending-booking-select", "pending-selected-count");
    });
  }

  // ── User-request select-all ───────────────────────────────────────────────
  const userSelectAll = document.getElementById("userRequestSelectAll");
  if (userSelectAll) {
    document.querySelectorAll(".user-request-select").forEach((c) => {
      c.addEventListener("change", () =>
        updateSelectedCount(".user-request-select", "user-selected-count"),
      );
    });
    userSelectAll.addEventListener("change", () => {
      document.querySelectorAll(".user-request-select").forEach((c) => {
        c.checked = userSelectAll.checked;
      });
      updateSelectedCount(".user-request-select", "user-selected-count");
    });
  }

  // ── Collapse chevron animation ────────────────────────────────────────────
  document
    .querySelectorAll('[data-bs-toggle="collapse"]')
    .forEach((trigger) => {
      const targetSel = trigger.dataset.bsTarget;
      const chevron = trigger.querySelector(".admin-chevron");
      if (!chevron || !targetSel) return;
      const target = document.querySelector(targetSel);
      if (!target) return;
      // Set initial rotation
      chevron.style.transition = "transform .2s ease";
      chevron.style.transform = target.classList.contains("show")
        ? "rotate(0deg)"
        : "rotate(-90deg)";
      target.addEventListener("show.bs.collapse", () => {
        chevron.style.transform = "rotate(0deg)";
      });
      target.addEventListener("hide.bs.collapse", () => {
        chevron.style.transform = "rotate(-90deg)";
      });
    });

  // ── Identity / supervisor toggle (access-request form) ───────────────────
  const supervisorsContainer = document.getElementById("supervisor-select");
  document.querySelectorAll(".identity-button").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      if (supervisorsContainer)
        supervisorsContainer.style.display =
          e.target.value === "Staff" ? "block" : "none";
    });
  });

  // ── TomSelect for admin "grant access" user search ────────────────────────
  const userSelect = document.getElementById("user_booking_select");
  if (userSelect && !userSelect.tomSelect) {
    userSelect.tomSelect = new TomSelect(userSelect, {
      plugins: { remove_button: { title: "Remove" } },
      valueField: "id",
      labelField: "name",
      searchField: ["name"],
      options: [],
      load(query, callback) {
        if (!query.length) return callback();
        fetch(`/sub_space_booking/users?query=${encodeURIComponent(query)}`)
          .then((r) => r.json())
          .then(callback)
          .catch(() => callback());
      },
    });
  }

  // ── Edit-page flatpickr ───────────────────────────────────────────────────
  document.getElementById("sub_space_booking_start_time")?.flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
  });
  document.getElementById("sub_space_booking_end_time")?.flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
  });

  // ── Calendar setup ────────────────────────────────────────────────────────
  const bookedCalendarEl = document.getElementById("booked-calendar");
  if (!bookedCalendarEl) return; // not on calendar tab, bail early

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

  // ---- Edit (existing booking) ---------------------------------------------
  function editEvent(arg) {
    document.getElementById("bookSave").style.display = "none";
    document.getElementById("bookUpdate").style.display = "block";
    document.getElementById("subspace").style.display = "block";
    document.getElementById("subspace_header").style.display = "block";
    document.getElementById("bookingModalLabel").innerText = "Update Booking";
    document.getElementById("sub_space_booking_id").value =
      arg.event.id.split("_")[1];
    document.getElementById("book-recurring").style.display = "none";
    document.getElementById("book-recurring-label").style.display = "none";

    fetch(
      `/sub_space_booking/get_sub_space_booking?id=${arg.event.id.split("_")[1]}`,
      {
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
      },
    )
      .then((r) => r.json())
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
      });
  }

  // ---- Flatpickr instances -------------------------------------------------
  start_picker = document.getElementById("book-start").flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
  });
  end_picker = document.getElementById("book-end").flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
  });
  recurring_picker = document.getElementById("book-recurring-end").flatpickr({
    enableTime: false,
    altInput: true,
    altFormat: "F j, Y",
  });

  // ---- Modal button wiring ------------------------------------------------
  document.getElementById("bookCancel").addEventListener("click", closeModal);
  document.getElementById("bookClose").addEventListener("click", closeModal);
  document.getElementById("bookSave").addEventListener("click", bookEvent);
  document.getElementById("bookUpdate").addEventListener("click", updateEvent);
  document.getElementById("bookDelete").addEventListener("click", deleteEvent);
  document
    .getElementById("bookRecurringDeleteOne")
    .addEventListener("click", deleteEvent);
  document
    .getElementById("bookRecurringDeleteRest")
    .addEventListener("click", deleteRecurringEvent);
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

  // ---- Book (POST) --------------------------------------------------------
  function bookEvent(e) {
    if (!validateDates()) return;
    e.target.setAttribute("disabled", "");

    const data = {
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
    };

    makeRequest(
      new Request("/sub_space_booking", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(data),
      }),
      e.target,
    );
  }

  // ---- Update (PATCH) -----------------------------------------------------
  function updateEvent() {
    if (!validateDates()) return;
    const btn = document.getElementById("bookUpdate");
    btn.setAttribute("disabled", "");

    const id = document.getElementById("sub_space_booking_id").value;
    const data = {
      sub_space_booking: {
        name: document.getElementById("book-name").value,
        description: document.getElementById("book-description").value,
        start_time: start_picker.input.value,
        end_time: end_picker.input.value,
        sub_space_id: document.getElementById("subspace").value,
        blocking: document.getElementById("book-blocking")?.checked ?? false,
      },
    };

    makeRequest(
      new Request(`/sub_space_booking/${id}/update`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(data),
      }),
      btn,
    );
  }

  // ---- Delete (DELETE) ----------------------------------------------------
  function deleteEvent() {
    if (!confirm("Delete this booking?")) return;
    const id = document.getElementById("sub_space_booking_id").value;
    makeRequest(
      new Request(`/sub_space_booking/${id}/delete/${id}`, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      }),
      document.getElementById("bookDelete"),
    );
  }

  function deleteRecurringEvent() {
    if (!confirm("Delete this and all remaining occurrences?")) return;
    const id = document.getElementById("sub_space_booking_id").value;
    makeRequest(
      new Request(`/sub_space_booking/${id}/delete_remaining_recurring`, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      }),
      document.getElementById("bookRecurringDeleteRest"),
    );
  }

  // ---- Shared fetch handler -----------------------------------------------
  function makeRequest(request, triggerBtn) {
    fetch(request)
      .then((r) => r.text())
      .then((text) => {
        let parsed;
        try {
          parsed = JSON.parse(text);
        } catch {
          parsed = null;
        }

        if (parsed?.errors) {
          // Re-enable the button
          triggerBtn?.removeAttribute("disabled");

          for (const error of parsed.errors) {
            const [type, ...rest] = error.split(" ");
            const message = rest.join(" ");

            if (["DurationHour", "DurationWeek", "TimeSlot"].includes(type)) {
              const toastEl = document.getElementById("booking_toast");
              if (toastEl) {
                document.getElementById("toast_text").innerText = message;
                document.getElementById("toast_title").innerText =
                  "Booking failed";
                bootstrap.Toast.getOrCreateInstance(toastEl).show();
              }
              closeModal();
              window.scrollTo(0, 0);
            } else {
              const feedback = document.createElement("div");
              feedback.className = "invalid-feedback";
              feedback.innerText = message || error;
              const field = document.getElementById(
                "book-" + type.toLowerCase(),
              );
              if (field && !field.classList.contains("is-invalid")) {
                field.classList.add("is-invalid");
                field.after(feedback);
              }
            }
          }
        } else {
          // Success — close modal and reload calendar data
          closeModal();
          bookedCalendar.refetchEvents();
          // If a hard redirect is needed (delete etc.), reload
          if (parsed === null) window.location.reload();
        }
      })
      .catch(() => {
        triggerBtn?.removeAttribute("disabled");
      });
  }

  // ---- FullCalendar -------------------------------------------------------
  const bookedCalendar = new Calendar(bookedCalendarEl, {
    initialDate: window.location.href.includes("start")
      ? new Date(new URLSearchParams(window.location.search).get("start"))
      : new Date(),
    plugins: [interactionPlugin, timeGridPlugin, listPlugin],
    height: "auto",
    headerToolbar: {
      left: "prev,today,next",
      center: "",
      right: "book,timeGridWeek",
    },
    customButtons: {
      book: { text: "Book", click: () => createEvent() },
    },
    views: {
      timeGridWeek: {
        dayHeaderFormat: { weekday: "short", day: "numeric", month: "short" },
      },
    },
    allDaySlot: false,
    timeZone: "America/New_York",
    initialView: "timeGridWeek",
    navLinks: true,
    slotEventOverlap: false,
    scrollTime: "07:00:00",
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
        // Attach CSRF token so Rails doesn't reject the JSON request
        extraParams: () => ({
          authenticity_token:
            document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        }),
        // Surface fetch errors in the console rather than silently failing
        failure: () => {
          console.error("FullCalendar failed to fetch bookings.");
        },
      },
    ],
    select: (arg) => createEvent(arg),
    eventClick: (arg) => editEvent(arg),
  });

  bookedCalendar.render();
}); // end turbo:load

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
