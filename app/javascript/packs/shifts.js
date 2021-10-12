import { Calendar } from '@fullcalendar/core';
import '@fullcalendar/common/main.css'
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import listPlugin from '@fullcalendar/list';

let calendarEl = document.getElementById('calendar');
const urlParams = new URLSearchParams(window.location.search);
const space_id = urlParams.get('space_id')

let calendar = new Calendar(calendarEl, {
    plugins: [ interactionPlugin, timeGridPlugin, listPlugin ],
    headerToolbar: {
        left: 'prev,today,next',
        center: 'title',
        right: 'timeGridWeek,timeGridDay'
    },
    allDaySlot: false,
    timeZone: 'America/New_York',
    initialView: 'timeGridWeek',
    navLinks: true,
    eventTimeFormat: {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    },
    dayMaxEvents: true,
    eventClick: function(info) {
        alert('Event: ' + info.event.title);
    },
    eventSources: [
        {
            url: `/admin/shifts/get_availabilities?space_id=${space_id}`,
        }
    ],
});

calendar.render();