document.addEventListener("DOMContentLoaded", async () => {
  const calContainer = document.getElementById("cal-container");

  // create dom element
  const calendarElement = document.createElement("add-to-calendar-button");

  try {
    const res = await fetch("/staff/shared_calendars/get_calendars");

    // for each calendar, create an h3 with name and create a button
    const { calendars } = await res.json();

    if (!calendars || calendars.length === 0) {
      const h3 = document.createElement("h3");
      h3.textContent = "No calendars available";
      calContainer.appendChild(h3);
      return;
    }

    calendars.forEach((cal) => {
      const h3 = document.createElement("h3");
      h3.textContent = cal.name;
      h3.classList.add("mt-4");
      calContainer.appendChild(h3);

      const calendarElement = document.createElement("add-to-calendar-button");
      calendarElement.setAttribute("name", cal.name);
      calendarElement.setAttribute("subscribe", "");
      calendarElement.setAttribute("icsFile", cal.url);
      calendarElement.setAttribute(
        "options",
        "'Google','Apple','Outlook.com','Microsoft 365','Microsoft Teams','iCal'",
      );
      calendarElement.setAttribute("buttonStyle", "flat");
      calendarElement.setAttribute("hideIconList", "");
      calendarElement.setAttribute("buttonsList", "");
      calendarElement.setAttribute("hideBackground", "");
      calendarElement.setAttribute("label", "Flat and Singleton");
      calendarElement.setAttribute("lightMode", "bodyScheme");

      // append to container
      calContainer.appendChild(calendarElement);
    });
  } catch (error) {
    console.error("Error fetching shifts:", error);
    document.getElementById("spinner").style.display = "none";
  }
});
