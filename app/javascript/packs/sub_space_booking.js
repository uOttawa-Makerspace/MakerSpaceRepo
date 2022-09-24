import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
let bookedCalendarEl = document.getElementById("booked-calendar");
if (bookedCalendarEl) {
  function createEvent(arg) {
    let modal = document.getElementById("bookModal");
    if (modal) {
      modal.style.display = "block";
      modal.classList.add("show");
      if (arg !== undefined && arg !== null) {
        start_picker.setDate(Date.parse(arg.startStr));
        end_picker.setDate(Date.parse(arg.endStr));
      }
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
  document.getElementById("bookCancel").addEventListener("click", closeModal);
  document.getElementById("bookClose").addEventListener("click", closeModal);
  document.getElementById("bookSave").addEventListener("click", bookEvent);
  function closeModal() {
    let modal = document.getElementById("bookModal");
    if (modal) {
      modal.style.display = "none";
      modal.classList.remove("show");
      document.getElementById("book-name").value = "";
      document.getElementById("book-description").value = "";
    }
  }
  function bookEvent(e) {
    let name = document.getElementById("book-name").value;
    let description = document.getElementById("book-description").value;
    let start_time = start_picker.selectedDates[0];
    let end_time = end_picker.selectedDates[0];
    let data = {
      name: name,
      description: description,
      start_time: start_time,
      end_time: end_time,
      room: new URLSearchParams(window.location.search).get("room"),
    };
    let url = "/sub_space_booking";
    let request = new Request(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(data),
    });
    fetch(request)
      .then((response) => response.text())
      .then((data) => {
        try {
          let errors = JSON.parse(data)["errors"];
          for (let error of errors) {
            let errorInput = error.split(" ")[0];
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
        } catch (e) {
          closeModal();
          Turbolinks.clearCache();
          Turbolinks.visit(window.location.href);
        }
      })
      .catch((error) => {
        console.log(error);
      });
  }
  let bookedCalendar = new Calendar(bookedCalendarEl, {
    plugins: [interactionPlugin, timeGridPlugin, listPlugin],
    height: "auto",
    headerToolbar: {
      left: "prev,today,next",
      center: "book",
      right: "timeGridWeek",
    },
    customButtons: {
      book: {
        text: `Book ${new URLSearchParams(window.location.search).get("room")}`,
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
    slotMinTime: "08:00:00",
    slotMaxTime: "18:00:00",
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
