import "flatpickr";
const start_time = document.getElementById("start_time").flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

document.getElementById("start_time_clear").addEventListener("click", () => {
  start_time.clear();
});

const end_time = document.getElementById("end_time").flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

document.getElementById("end_time_clear").addEventListener("click", () => {
  end_time.clear();
});

start_time.config.onClose = [
  () => {
    end_time.set("minDate", start_time.selectedDates[0]);
    if (end_time.selectedDates[0] <= start_time.selectedDates[0]) {
      end_time.setDate(start_time.selectedDates[0]);
    }
  },
];

end_time.config.onClose = [
  () => {
    start_time.set("maxDate", end_time.selectedDates[0]);
  },
];

if (document.getElementById("userId")) {
  if (!document.getElementById("userId").tomselect) {
    new TomSelect("#userId");
  }
}
