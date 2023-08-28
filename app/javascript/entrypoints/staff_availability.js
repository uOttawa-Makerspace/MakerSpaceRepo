import TomSelect from "tom-select";
import "flatpickr";

const recurring_checkbox = document.getElementById("recurring");
//recurring_checkbox.value = recurring_checkbox.checked ? 1 : 0;
const day_input = document.getElementById("day");
const start_date_input = document.getElementById("start_date");
const end_date_input = document.getElementById("end_date");

const start_time = document.getElementById("start_time").flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

const end_time = document.getElementById("end_time").flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

const start_date = start_date_input.flatpickr({
  enableTime: false,
  noCalendar: false,
  dateFormat: "Y-m-d",
});

const end_date = end_date_input.flatpickr({
  enableTime: false,
  noCalendar: false,
  dateFormat: "Y-m-d",
});

recurring_checkbox.addEventListener("change", function () {
  if (this.checked) {
    day_input.parentElement.style.display = "block";
    start_date_input.parentElement.parentElement.style.display = "none";
    end_date_input.parentElement.parentElement.style.display = "none";
  } else {
    day_input.parentElement.style.display = "none";
    start_date_input.parentElement.parentElement.style.display = "block";
    end_date_input.parentElement.parentElement.style.display = "block";
  }
});

document.getElementById("start_time_clear").addEventListener("click", () => {
  start_time.clear();
});

document.getElementById("end_time_clear").addEventListener("click", () => {
  end_time.clear();
});

document.getElementById("start_date_clear").addEventListener("click", () => {
  start_date.clear();
});

document.getElementById("end_date_clear").addEventListener("click", () => {
  end_date.clear();
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
    new TomSelect("#userId", {
      maxOptions: null,
    });
  }
}
