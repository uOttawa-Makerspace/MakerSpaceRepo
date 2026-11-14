import "flatpickr";
import { flatpickrOptions } from "../src/page_locale.js";

const depositDateInput = document.getElementById("deposit-return-date");
if (depositDateInput) {
  const depositDatePicker = depositDateInput.flatpickr(
    flatpickrOptions(depositDateInput, {
      enableTime: false,
      noCalendar: false,
      dateFormat: "Y-m-d",
    }),
  );

  document
    .getElementById("deposit-return-date-clear")
    .addEventListener("click", () => {
      depositDatePicker.clear();
    });
}
