import "./fullcalendar_setup_staff_unavailabilities";
import { addUnavailabilityClick } from "./unavailabilities_helpers.js";
import "./manage_unavailabilities";

document.addEventListener("turbo:load", () => {
  document
    .getElementById("addUnavailabilityButton")
    .addEventListener("click", addUnavailabilityClick);

  // external calendars
  [...document.getElementsByClassName("calendar-delete-button")].forEach(
    (btn) =>
      btn.addEventListener("click", (el) => {
        el.target.closest("button").parentNode.remove();
      }),
  );

  document.getElementById("new-calendar").addEventListener("click", () => {
    const clone = document.getElementById("new-link-input").cloneNode(true);
    document.getElementById("link-container").append(clone);
    clone.removeAttribute("id");
    clone.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
    clone.querySelector("button").addEventListener("click", (el) => {
      el.target.closest("button").parentNode.remove();
    });
    clone.style.visibility = "visible";
  });
});
