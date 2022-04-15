import 'jquery'
import 'flatpickr'
import TomSelect from "tom-select";

const start_time = jQuery('#start_time').flatpickr({
    enableTime: true,
    noCalendar: true,
    dateFormat: "H:i",
    time_24hr: true
});

jQuery('#start_time_clear').click(() => {
    start_time.clear()
})

const end_time = jQuery('#end_time').flatpickr({
    enableTime: true,
    noCalendar: true,
    dateFormat: "H:i",
    time_24hr: true
});

jQuery('#end_time_clear').click(() => {
    end_time.clear()
})

start_time.config.onClose = [() => {
    end_time.set("minDate", start_time.selectedDates[0]);
    if (end_time.selectedDates[0] <= start_time.selectedDates[0]) {
        end_time.setDate(start_time.selectedDates[0]);
    }
}];

end_time.config.onClose = [() => {
    start_time.set("maxDate", end_time.selectedDates[0]);
}];

new TomSelect("#userId");