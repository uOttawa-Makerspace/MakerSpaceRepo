import { Calendar, elementClosest } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
let bookedCalendarEl = document.getElementById("booked-calendar");
if (bookedCalendarEl) {
  function createEvent(arg) {
    let modal = document.getElementById("bookModal");
    toggleRecurring();
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
    let data = {
      sub_space_booking: {
        name: document.getElementById("book-name").value,
        description: document.getElementById("book-description").value,
        start_time: start_picker.selectedDates[0],
        end_time: end_picker.selectedDates[0],
        sub_space_id: new URLSearchParams(window.location.search).get("room"),
        recurring: document.getElementById("book-recurring").checked,
        recurring_end: recurring_picker.selectedDates[0],
        recurring_frequency: document.getElementById("book-recurring-type")
          .value,
      },
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
            if (
              errorInput === "DurationHour" ||
              errorInput === "DurationWeek"
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
document.addEventListener("turbolinks:render", ready);
function ready() {
  [...document.getElementsByClassName("nav-link")].forEach((el) => {
    el.addEventListener("click", (e) => {
      console.log(e.target);
    });
  });
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
