import { Calendar } from '@fullcalendar/core';
import '@fullcalendar/common/main.css'
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import listPlugin from '@fullcalendar/list';
import googleCalendarPlugin from '@fullcalendar/google-calendar';
import TomSelect from 'tom-select';

let calendarEl = document.getElementById('calendar');
const urlParams = new URLSearchParams(window.location.search);
const space_id = urlParams.get('space_id');
let modal = document.getElementById('shiftModal');
let start_datetime = document.getElementById("start-datetime");
let end_datetime = document.getElementById("end-datetime");
let modalSave = document.getElementById("shiftSave");
let modalClose = document.getElementById("shiftCancel");
let modalUserId = document.getElementById("modalUserId");
let modalReason = document.getElementById("modalReason");
let sourceShow = {
    google: "none",
    transparent: "none",
    staffNeeded: "none",
};

let calendar = new Calendar(calendarEl, {
    plugins: [interactionPlugin, timeGridPlugin, listPlugin, googleCalendarPlugin],
    customButtons: {
        addNewEvent: {
            text: "+",
            click: () => {
                createEvent();
            },
        },
    },
    headerToolbar: {
        left: 'prev,today,next',
        center: '',
        right: 'addNewEvent,timeGridWeek,timeGridDay'
    },
    slotEventOverlap: false,
    allDaySlot: false,
    timeZone: 'America/New_York',
    initialView: 'timeGridWeek',
    navLinks: true,
    selectable: true,
    selectMirror: true,
    slotMinTime: "07:00:00",
    slotMaxTime: "22:00:00",
    eventTimeFormat: {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    },
    editable: true,
    dayMaxEvents: true,
    eventSources: [
        {
            id: 'transparent',
            url: `/admin/shifts/get_availabilities?transparent=true&space_id=${space_id}`,
            editable: false,
        },
        {
            id: 'shifts',
            url: `/admin/shifts/get_shifts?space_id=${space_id}`,
        },
        {
            id: 'google',
            googleCalendarApiKey: 'AIzaSyCMNxnP0pdKHtZaPBJAtfv68A2h6qUeuW0',
            googleCalendarId: 'c_d7liojb08eadntvnbfa5na9j98@group.calendar.google.com',
            color: 'rgba(255,31,31,0.4)',
            editable: false,
        },
        {
            id: 'staffNeeded',
            url: `/admin/shifts/get_staff_needed?space_id=${space_id}`,
            color: 'rgba(40,40,40,0.4)',
            editable: false,
        },
    ],
    select: (arg) => {
        createEvent(arg);
    },
    eventClick: (arg) => {
        if (arg.event.source.id === 'shifts') {
            removeEvent(arg);
        }
    },
    eventDrop: (arg) => {
        modifyEvent(arg);
    },
    eventResize: (arg) => {
        modifyEvent(arg);
    },
    eventOrder: (a, b) => {
        if ((a.title.includes("is unavailable") && b.title.includes("is unavailable")) || (!a.title.includes("is unavailable") && !b.title.includes("is unavailable"))) {
            return 0;
        } else if(a.title.includes("is unavailable")) {
            return -1;
        } else {
            return 1;
        }
    },
});
calendar.render();

let createEvent = (arg = undefined) => {
    openModal(arg);
}

let createCalendarEvent = () => {
    let selected_users = [];
    for (let option of modalUserId.options) {
        if (option.selected) {
            selected_users.push(option.value);
        }
    }
    fetch(`/admin/shifts?space_id=${space_id}`, {
        method: "POST",
        headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({start_datetime: start_datetime.value, end_datetime: end_datetime.value, format: 'json', user_id: selected_users, reason: modalReason.value})
    }).then(response => response.json()).then(
        data => {
            calendar.addEvent({
                title: data.name,
                start: data.start,
                end: data.end,
                allDay: false,
                id: data['id'],
                color: data.color,
                className: data.className
            }, "shifts")
            calendar.unselect();
            closeModal();
        },
    ).catch((error) => {
        console.log('An error occurred: ' + error.message);
    });
}

let openModal = (arg) => {
    modal.style.display = "block"
    modal.classList.add("show")

    if (arg !== undefined && arg !== null){
        start_picker.setDate(Date.parse(arg.startStr));
        end_picker.setDate(Date.parse(arg.endStr));
    }

}
let closeModal = () => {
    modalUserIdSelect.clear();
    modalReason.value = "";
    start_picker.clear();
    end_picker.clear();
    modal.style.display = "none";
    modal.classList.remove("show");
    modalSave.removeEventListener('click', createCalendarEvent);
}

window.onclick = function(event) {
    if (event.target === modal) {
        closeModal()
    }
}

let modifyEvent = (arg) => {
    fetch("/admin/shifts/"+arg.event.id, {
        method: "PUT",
        headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({start_datetime: arg.event.start, end_datetime: arg.event.end, format: 'json'})
    }).then((response) => {
        if (!response.ok) {
            arg.revert();
        }
    }).catch((error) => {
        console.log('An error occurred: ' + error.message);
    });
}

let removeEvent = (arg) => {
    if (confirm('Are you sure you want to delete this event?')) {
        fetch("/admin/shifts/"+arg.event.id, {
            method: "DELETE",
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({format: 'json'})
        }).then((response) => {
            if (response.ok) {
                arg.event.remove()
            } else {
                console.log('An error occurred');
            }
        }).catch((error) => {
            console.log('An error occurred: ' + error.message);
        });
    }
}

const hideShowEvents = (eventName, toggleId, text) => {
    let allEvents = calendar.getEvents();
    for (let ev of allEvents) {
        if (ev.source.id === eventName) {
            ev.setProp("display", sourceShow[eventName]);
            document.getElementById(toggleId).innerText = `${ sourceShow[eventName] === "block" ? 'Hide' : 'Show' } ${text}`;
        }
    }

    if (sourceShow[eventName] === "none") {
        sourceShow[eventName] = "block";
    } else {
        sourceShow[eventName] = "none";
    }
}

document.getElementById("hide-show-unavailabilities").addEventListener("click", () => {
    hideShowEvents("transparent", "hide-show-unavailabilities", "Unavailabilities");
})

document.getElementById("hide-show-google-events").addEventListener("click", () => {
    hideShowEvents("google", "hide-show-google-events", "Event");
})

document.getElementById("hide-show-staff-needed").addEventListener("click", () => {
    hideShowEvents("staffNeeded", "hide-show-staff-needed", "Staff Needed");
})

const start_picker = start_datetime.flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
});

const end_picker = end_datetime.flatpickr({
    enableTime: true,
    time_24hr: true,
    altInput: true,
    altFormat: "F j, Y at H:i",
});

modalClose.addEventListener("click", closeModal);

modalSave.addEventListener('click', () => {
    createCalendarEvent();
})

window.toggleVisibility = (name) => {
    Array.from(document.getElementsByClassName(name)).forEach((item) => {
        if (item.style.display === "none") {
            item.style.display = "block";
            document.getElementById(name).innerText = "Hide";
        } else {
            item.style.display = "none";
            document.getElementById(name).innerText = "Show";
        }
    });
}

let modalUserIdSelect = new TomSelect("#modalUserId",{
    maxItems: 3
});