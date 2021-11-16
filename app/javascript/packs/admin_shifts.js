import { Calendar } from '@fullcalendar/core';
import '@fullcalendar/common/main.css'
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import listPlugin from '@fullcalendar/list';

document.addEventListener("turbolinks:load", () => {
    let calendarEl = document.getElementById('calendar');
    const urlParams = new URLSearchParams(window.location.search);
    const space_id = urlParams.get('space_id');
    let modal = document.getElementById('shiftModal');
    let start_datetime = document.getElementById("start-datetime");
    let end_datetime = document.getElementById("end-datetime");
    let sourceShow = "none";

    let calendar = new Calendar(calendarEl, {
        plugins: [interactionPlugin, timeGridPlugin, listPlugin],
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
        views: {
            timeGridWeek: {
                dayHeaderFormat: {
                    weekday: 'long',
                },
            },
        },
        slotEventOverlap: false,
        allDaySlot: false,
        timeZone: 'America/New_York',
        initialView: 'timeGridWeek',
        navLinks: true,
        selectable: true,
        selectMirror: true,
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
            }
        ],
        select: (arg) => {
            createEvent(arg);
        },
        eventClick: (arg) => {
            if (arg.event.source.id !== 'transparent') {
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
        let modalSave = document.getElementById("shiftSave");
        let modalClose = document.getElementById("shiftCancel");
        let modalUserId = document.getElementById("modalUserId");
        let modalReason = document.getElementById("modalReason");

        openModal(arg);

        modalClose.addEventListener("click", closeModal);

        modalSave.addEventListener('click', () => {
            fetch("/admin/shifts", {
                method: "POST",
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({start_datetime: start_datetime.value, end_datetime: end_datetime.value, format: 'json', user_id: modalUserId.value, reason: modalReason.value})
            }).then(response => response.json()).then(
                data => {
                    calendar.addEvent({
                        title: data.name,
                        start: data.start,
                        end: data.end,
                        allDay: false,
                        id: data['id'],
                        color: data.color
                    }, "shifts")
                    calendar.unselect();
                    closeModal();
                },
            ).catch((error) => {
                console.log('An error occurred: ' + error.message);
            });
        }, {once : true})
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
        modalUserId.value = "";
        modalReason.value = "";
        start_picker.clear();
        end_picker.clear();
        modal.style.display = "none"
        modal.classList.remove("show")
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

    document.getElementById("hide-show-unavailabilities").addEventListener("click", () => {
        let allEvents = calendar.getEvents();
        for (let ev of allEvents) {
            if (ev.source.id === "transparent") {
                ev.setProp("display", sourceShow);
            }
        }

        if (sourceShow === "none") {
            sourceShow = "block";
        } else {
            sourceShow = "none";
        }
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

});
