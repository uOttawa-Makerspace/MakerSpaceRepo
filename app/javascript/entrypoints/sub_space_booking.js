// The booking page's scripts are Stimulus controllers (booking_*_controller.js,
// recurring_approval, select_all, supervisor_field, date_time_picker). This
// entrypoint stays because the layout loads it with data-turbo-track="reload",
// so a Turbo visit between the booking pages and the rest of the site is a full
// page load, as before.
