document.addEventListener("turbo:load", () => {
  function refreshFieldsets(e) {
    const dateRange = document.querySelector("fieldset#dateRange");
    const semester = document.querySelector("fieldset#dateSemester");
    // Disable all fieldsets
    document.querySelectorAll("fieldset.date-fieldset").forEach((i) => {
      i.setAttribute("hidden", "");
      i.setAttribute("disabled", "");
    });
    console.log(e.target.dataset.show);
    let showFieldset = document.querySelector(e.target.dataset.show);
    showFieldset.removeAttribute("hidden");
    showFieldset.removeAttribute("disabled");
  }

  // Attach events
  const dateFormat = document.querySelector("#CSVDumpForm").date_format;
  for (let i = 0; i < dateFormat.length; i++) {
    dateFormat[i].addEventListener("change", (e) => refreshFieldsets(e));
  }
});
