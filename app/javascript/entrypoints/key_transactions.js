const depositDateInput = document.getElementById("deposit-return-date");
if (depositDateInput) {
  const depositDatePicker = depositDateInput.flatpickr({
    enableTime: false,
    noCalendar: false,
    dateFormat: "Y-m-d",
  });

  document
    .getElementById("deposit-return-date-clear")
    .addEventListener("click", () => {
      depositDatePicker.clear();
    });
}
