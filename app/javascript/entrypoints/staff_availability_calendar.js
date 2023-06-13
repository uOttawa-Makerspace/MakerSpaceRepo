import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import TomSelect from "tom-select";

let calendarEl = document.getElementById("user_availabilities_calendar");
const urlParams = new URLSearchParams(window.location.search);
const staff_id = urlParams.get("staff_id");
const time_period_id = urlParams.get("time_period_id");

let calendar = new Calendar(calendarEl, {
  plugins: [interactionPlugin, timeGridPlugin, listPlugin],
  headerToolbar: {
    left: "prev,today,next",
    center: "",
    right: "timeGridWeek,timeGridDay",
  },
  views: {
    timeGridWeek: {
      dayHeaderFormat: {
        weekday: "long",
      },
    },
  },
  allDaySlot: false,
  timeZone: "America/New_York",
  initialView: "timeGridWeek",
  navLinks: true,
  selectable: true,
  selectMirror: true,
  slotMinTime: "07:00:00",
  slotMaxTime: "22:00:00",
  eventTimeFormat: {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  },
  editable: true,
  dayMaxEvents: true,
  slotEventOverlap: false,
  eventSources: [
    {
      url: `/staff_availabilities/get_availabilities?staff_id=${staff_id}${
        time_period_id ? "&time_period_id=" + time_period_id : ""
      }`,
    },
  ],
  select: function (arg) {
    createEvent(arg);
  },
  eventClick: function (arg) {
    removeEvent(arg);
  },
  eventDrop: function (arg) {
    modifyEvent(arg);
  },
  eventResize: function (arg) {
    modifyEvent(arg);
  },
});
calendar.render();

let createEvent = (arg) => {
  fetch("/staff_availabilities", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      staff_id: staff_id,
      start_date: arg.start,
      end_date: arg.end,
      format: "json",
      ...(time_period_id && { time_period_id: time_period_id }),
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      calendar.addEvent({
        title: "Unavailable",
        start: arg.start,
        end: arg.end,
        allDay: arg.allDay,
        id: data["id"],
      });
      calendar.unselect();
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

let modifyEvent = (arg) => {
  fetch("/staff_availabilities/" + arg.event.id, {
    method: "PUT",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      start_date: arg.event.start,
      end_date: arg.event.end,
      format: "json",
    }),
  })
    .then((response) => {
      if (!response.ok) {
        arg.revert();
      }
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

let removeEvent = (arg) => {
  if (confirm("Are you sure you want to delete this event?")) {
    fetch("/staff_availabilities/" + arg.event.id, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ format: "json" }),
    })
      .then((response) => {
        if (response.ok) {
          arg.event.remove();
        } else {
          console.log("An error occurred");
        }
      })
      .catch((error) => {
        console.log("An error occurred: " + error.message);
      });
  }
};
if (document.getElementById("staff_id")) {
  if (!document.getElementById("staff_id").tomselect) {
    new TomSelect("#staff_id", {
      maxItems: 1,
      placeholder: "Select Staff",
      maxOptions: null,
    });
  }
}
