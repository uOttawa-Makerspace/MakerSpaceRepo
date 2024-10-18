import { Calendar, elementClosest } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import TomSelect from "tom-select";
document.addEventListener("turbo:load", function () {
  let bookedCalendarEl = document.getElementById("booked-calendar");
  if (bookedCalendarEl) {
    function createEvent(arg) {
      let modal = document.getElementById("bookModal");

      document.getElementById("bookSave").style.display = "block";
      document.getElementById("bookUpdate").style.display = "none";
      document.getElementById("bookDelete").style.display = "none";
      document.getElementById("bookingModalLabel").innerText = "New Booking";
      document.getElementById("book-recurring").style.display = "inline-block";
      document.getElementById("book-recurring-label").style.display =
        "inline-block";

      toggleRecurring();
      if (modal) {
        modal.style.display = "block";
        modal.classList.add("show");
        if (arg !== undefined && arg !== null) {
          start_picker.setDate(Date.parse(arg.startStr));
          end_picker.setDate(Date.parse(arg.endStr));
        }
        modal.querySelector("#book-name").focus();
      }
    }
    function editEvent(arg) {
      let modal = document.getElementById("bookModal");

      document.getElementById("bookSave").style.display = "none";
      document.getElementById("bookUpdate").style.display = "block";
      document.getElementById("bookingModalLabel").innerText = "Update Booking";
      document.getElementById("sub_space_booking_id").value =
        arg.event.id.split("_")[1];
      document.getElementById("book-recurring").style.display = "none";
      document.getElementById("book-recurring-label").style.display = "none";

      if (modal) {
        fetch(
          "/sub_space_booking/get_sub_space_booking?id=" +
            arg.event.id.split("_")[1],
          {
            method: "GET",
            headers: {
              Accept: "application/json",
              "Content-Type": "application/json",
            },
          }
        )
          .then((response) => response.json())
          .then((data) => {
            document.getElementById("book-name").value = data.name;
            document.getElementById("book-description").value =
              data.description;
            start_picker.setDate(Date.parse(data.start_time.slice(0, -6)));
            end_picker.setDate(Date.parse(data.end_time.slice(0, -6)));

            document.getElementById("book-recurring").checked = false;
            const blockingElement = document.getElementById("book-blocking");
            if (blockingElement) {
              blockingElement.checked = data.blocking;
            }

            document.getElementById("bookDelete").style.display =
              data.recurring_booking_id == null ? "block" : "none";
            bookDeleteRecurringDropdown.style.display =
              data.recurring_booking_id == null ? "none" : "block";

            modal.style.display = "block";
            modal.classList.add("show");

            toggleRecurring();
          });
      }
    }
    let start_picker = document.getElementById("book-start").flatpickr({
      enableTime: true,
      time_24hr: true,
      altInput: true,
      altFormat: "F j, Y at H:i",
    });
    let end_picker = document.getElementById("book-end").flatpickr({
      enableTime: true,
      time_24hr: true,
      altInput: true,
      altFormat: "F j, Y at H:i",
    });
    let recurring_picker = document
      .getElementById("book-recurring-end")
      .flatpickr({
        enableTime: false,
        altInput: true,
        altFormat: "F j, Y",
      });

    document.getElementById("bookCancel").addEventListener("click", closeModal);
    document.getElementById("bookClose").addEventListener("click", closeModal);
    document.getElementById("bookSave").addEventListener("click", bookEvent);
    document
      .getElementById("bookUpdate")
      .addEventListener("click", updateEvent);
    document
      .getElementById("bookDelete")
      .addEventListener("click", deleteEvent);
    // Same functionality, just a different label
    document
      .getElementById("bookRecurringDeleteOne")
      .addEventListener("click", deleteEvent);
    // This calls a different REST endpoint
    document
      .getElementById("bookRecurringDeleteRest")
      .addEventListener("click", deleteRecurringEvent);
    document
      .getElementById("book-recurring")
      .addEventListener("change", toggleRecurring);
    function toggleRecurring() {
      let recurring = document.getElementById("book-recurring");
      let recurringElems = [
        document.getElementById("book-recurring-end"),
        document.getElementById("book-recurring-end-label"),
        document.getElementById("book-recurring-type"),
        document.getElementById("book-recurring-type-label"),
        document.getElementsByClassName("flatpickr")[0],
      ];
      if (recurring.checked) {
        recurringElems.forEach((elem) => {
          elem.style.display = "block";
        });
      } else {
        recurringElems.forEach((elem) => {
          elem.style.display = "none";
        });
      }
    }
    function closeModal() {
      let modal = document.getElementById("bookModal");
      if (modal) {
        modal.style.display = "none";
        modal.classList.remove("show");
        document.getElementById("book-name").value = "";
        document.getElementById("book-description").value = "";
        recurring_picker.setDate(null);
      }
    }
    function bookEvent(e) {
      e.target.setAttribute("disabled", "");
      if (start_picker.selectedDates[0] >= end_picker.selectedDates[0]) {
        document
          .getElementById("end-date-validation")
          .classList.remove("d-none");
        document.getElementById("book-end").classList.add("is-invalid");
        end_picker.altInput.classList.add("is-invalid");
        return;
      } else {
        document.getElementById("end-date-validation").classList.add("d-none");
        document.getElementById("book-end").classList.remove("is-invalid");
        end_picker.altInput.classList.remove("is-invalid");
      }

      let data = {
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
          blocking: document.getElementById("book-blocking")
            ? document.getElementById("book-blocking").checked
            : false,
        },
      };
      let url = "/sub_space_booking";
      let request = new Request(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(data),
      });

      makeRequest(request);
    }
    function updateEvent() {
      if (start_picker.selectedDates[0] >= end_picker.selectedDates[0]) {
        document
          .getElementById("end-date-validation")
          .classList.remove("d-none");
        document.getElementById("book-end").classList.add("is-invalid");
        end_picker.altInput.classList.add("is-invalid");
        return;
      } else {
        document.getElementById("end-date-validation").classList.add("d-none");
        document.getElementById("book-end").classList.remove("is-invalid");
        end_picker.altInput.classList.remove("is-invalid");
      }

      let data = {
        sub_space_booking: {
          name: document.getElementById("book-name").value,
          description: document.getElementById("book-description").value,
          start_time: start_picker.input.value,
          end_time: end_picker.input.value,
          blocking: document.getElementById("book-blocking")
            ? document.getElementById("book-blocking").checked
            : false,
        },
      };

      let sub_space_booking_id = document.getElementById(
        "sub_space_booking_id"
      ).value;
      let url = `/sub_space_booking/${sub_space_booking_id}/update`;

      let request = new Request(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(data),
      });

      makeRequest(request);
    }
    function deleteEvent() {
      let sub_space_booking_id = document.getElementById(
        "sub_space_booking_id"
      ).value;
      let url = `/sub_space_booking/${sub_space_booking_id}/delete/${sub_space_booking_id}`;
      let request = new Request(url, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        // No body needed
      });

      makeRequest(request);
    }
    function deleteRecurringEvent() {
      //let recurring_booking_id = document.getElementById("recurring_booking_id").value
      let sub_space_booking_id = document.getElementById(
        "sub_space_booking_id"
      ).value;
      let url = `/sub_space_booking/${sub_space_booking_id}/delete_remaining_recurring`;
      let request = new Request(url, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        // Server doesn't allow body for HTTP DELETE
      });

      makeRequest(request);
    }
    function makeRequest(request) {
      fetch(request)
        .then((response) => response.text())
        .then((data) => {
          try {
            let errors = JSON.parse(data)["errors"];
            console.log(errors);
            for (let error of errors) {
              let errorInput = error.split(" ")[0];
              if (
                errorInput === "DurationHour" ||
                errorInput === "DurationWeek" ||
                errorInput == "TimeSlot"
              ) {
                let toastEl = document.getElementById("booking_toast");
                if (toastEl) {
                  document.getElementById("toast_text").innerText = error
                    .split(" ")
                    .slice(1)
                    .join(" ");
                  document.getElementById("toast_title").innerText =
                    "Your booking failed";
                  bootstrap.Toast.getOrCreateInstance(toastEl).show();
                  closeModal();
                  window.scrollTo(0, 0);
                }
              } else {
                let errorText = error.split(" ").slice(1).join(" ");
                let feedback = document.createElement("div");
                feedback.classList.add("invalid-feedback");
                feedback.innerText = errorText;
                let errorEl = document.getElementById(
                  "book-" + errorInput.toLowerCase()
                );
                if (errorEl && !errorEl.classList.contains("is-invalid")) {
                  errorEl.classList.add("is-invalid");
                  errorEl.after(feedback);
                }
              }
            }
          } catch (e) {
            console.log(e);
            closeModal();
            window.location.reload();
          }
        })
        .catch((error) => {
          console.log(error);
        });
    }
    let bookedCalendar = new Calendar(bookedCalendarEl, {
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
        book: {
          text: "Book",
          click: () => {
            createEvent();
          },
        },
      },
      views: {
        timeGridWeek: {
          dayHeaderFormat: {
            weekday: "short",
            day: "numeric",
            month: "short",
          },
        },
      },
      allDaySlot: false,
      timeZone: "America/New_York",
      initialView: "timeGridWeek",
      navLinks: true,
      slotEventOverlap: false,
      slotMinTime: "06:00:00",
      slotMaxTime: "22:00:00",
      selectable: true,
      eventTimeFormat: {
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      },
      dayMaxEvents: true,
      eventSources: [
        {
          id: "booked",
          url: `/sub_space_booking/bookings?room=${new URLSearchParams(
            window.location.search
          ).get("room")}`,
        },
      ],
      select: function (arg) {
        createEvent(arg);
      },
      eventClick: (arg) => {
        editEvent(arg);
      },
    });
    bookedCalendar.render();
  }
  let userSelect = document.getElementById("user_booking_select");
  if (userSelect) {
    if (!userSelect.tomSelect) {
      userSelect.tomSelect = new TomSelect(userSelect, {
        plugins: {
          remove_button: {
            title: "Remove this item",
          },
        },
        valueField: "id",
        labelField: "name",
        searchField: ["name"],
        options: [],
        load: function (query, callback) {
          if (!query.length) return callback();
          fetch(`/sub_space_booking/users?query=${encodeURIComponent(query)}`)
            .then((res) => res.json())
            .then((res) => {
              callback(res);
            })
            .catch((err) => {
              callback();
            });
        },
      });
    }
  }
  let editStart = document.getElementById("sub_space_booking_start_time");
  if (editStart) {
    editStart.flatpickr({
      enableTime: true,
      time_24hr: true,
      altInput: true,
      altFormat: "F j, Y at H:i",
    });
  }
  let editEnd = document.getElementById("sub_space_booking_end_time");
  if (editEnd) {
    editEnd.flatpickr({
      enableTime: true,
      time_24hr: true,
      altInput: true,
      altFormat: "F j, Y at H:i",
    });
  }

  const commentsContainer = document.getElementById("comments-container");
  const identitySelects = document.querySelectorAll(".identity-button");
  const supervisorsContainer = document.getElementById("supervisor-select");
  if (commentsContainer && identitySelects && supervisorsContainer) {
    identitySelects.forEach((button) => {
      button.addEventListener("click", (e) => {
        if (e.target.value === "Other") {
          commentsContainer.style.display = "block";
        } else {
          commentsContainer.style.display = "none";
        }

        if (e.target.value === "Staff") {
          supervisorsContainer.style.display = "block";
        } else {
          supervisorsContainer.style.display = "none";
        }
      });
    });
  }

  const selectAllUsersCheckbox = document.getElementById(
    "userRequestSelectAll"
  );
  selectAllUsersCheckbox.addEventListener("change", function () {
    const checkboxes = document.querySelectorAll(".user-request-select");
    checkboxes.forEach(function (checkbox) {
      checkbox.checked = selectAllUsersCheckbox.checked;
    });
  });

  document
    .getElementById("pending_bookings_select_all")
    .addEventListener("change", (e) => {
      document.querySelectorAll(".pending-booking-select").forEach((c) => {
        c.checked = e.currentTarget.checked;
      });
    });
});
document.addEventListener("turbo:render", ready);
function ready() {
  const anchor = window.location.hash.substring(1);
  const pending_table = new URLSearchParams(window.location.search).get(
    "pending_page"
  );
  const approved_table = new URLSearchParams(window.location.search).get(
    "approved_page"
  );
  const denied_table = new URLSearchParams(window.location.search).get(
    "denied_page"
  );
  const old_pending_table = new URLSearchParams(window.location.search).get(
    "old_pending_page"
  );
  const old_approved_table = new URLSearchParams(window.location.search).get(
    "old_approved_page"
  );
  const old_denied_table = new URLSearchParams(window.location.search).get(
    "old_denied_page"
  );
  const urls = [
    pending_table,
    approved_table,
    denied_table,
    old_pending_table,
    old_approved_table,
    old_denied_table,
  ];
  const param = pending_table
    ? "pending-accordion"
    : approved_table
    ? "approved-accordion"
    : denied_table
    ? "declined-accordion"
    : old_pending_table
    ? "past-pending-accordion"
    : old_approved_table
    ? "past-approved-accordion"
    : old_denied_table
    ? "past-declined-accordion"
    : null;
  if (anchor === "") {
    if (param) {
      makeActive("booking-admin-tab", param);
      // Remove urls from url bar
      let url = new URL(window.location.href);
      for (let u of urls) {
        if (u) {
          url.searchParams.delete(u);
        }
      }
      window.history.replaceState({}, document.title, url.href);
    } else {
      makeActive("booking-calendar-tab", null);
    }
  } else {
    makeActive(anchor, null);
  }
}
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
    table.scrollIntoView({
      behavior: "smooth",
      block: "start",
      inline: "nearest",
    });
    window.scrollBy(
      0,
      -7 * parseFloat(getComputedStyle(document.documentElement).fontSize)
    );
  }
}
let tabButtons = document.getElementsByClassName("tab-link");
[...tabButtons].forEach((button) => {
  button.addEventListener("click", (event) => {
    event.stopPropagation();
    event.preventDefault();
    let tab = button.id.split("-")[0];
    makeActive(tab, null);
  });
});
ready();

document.addEventListener("DOMContentLoaded", function () {});
