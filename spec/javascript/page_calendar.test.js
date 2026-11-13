// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";

import { pageCalendar } from "../../app/javascript/src/page_calendar.js";

// The real FullCalendar, drawn on a page of the given language with the
// toolbar the staff calendars use.
function draw(lang, options = {}) {
  document.body.innerHTML = `<div id="cal"><p id="stale">old</p></div>`;
  document.documentElement.setAttribute("lang", lang);
  const target = document.getElementById("cal");
  const calendar = pageCalendar(target, {
    plugins: [timeGridPlugin, dayGridPlugin],
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today",
      center: "title",
      right: "timeGridWeek,dayGridMonth",
    },
    ...options,
  });
  calendar.render();
  const name = (button) => target.querySelector(`.fc-${button}-button`).title;
  return { calendar, target, name };
}

let drawn;
afterEach(() => drawn?.calendar.destroy());

describe("pageCalendar", () => {
  it("names the toolbar buttons in English on an English page", () => {
    drawn = draw("en");

    expect(drawn.name("prev")).toBe("Previous week");
    expect(drawn.name("next")).toBe("Next week");
    expect(drawn.name("today")).toBe("This week");
    expect(drawn.name("dayGridMonth")).toBe("month view");
  });

  it("names the toolbar buttons in French on a French page", () => {
    drawn = draw("fr");

    expect(drawn.name("prev")).toBe("Précédent");
    expect(drawn.name("next")).toBe("Suivant");
    expect(drawn.name("today")).toBe("Aujourd'hui");
    expect(drawn.name("dayGridMonth")).toBe("Mois");
    expect(drawn.target.querySelector(".fc-today-button").textContent).toBe(
      "Aujourd'hui",
    );
  });

  it("keeps Sunday as the first day of the week in French", () => {
    drawn = draw("fr", { initialDate: "2027-03-17" });

    expect(drawn.calendar.view.activeStart.getDay()).toBe(0);
  });

  it("empties the target, draws in it and hides the chevrons from assistive technology", () => {
    drawn = draw("en");

    expect(drawn.target.querySelector("#stale")).toBeNull();
    expect(drawn.target.querySelector(".fc-view")).not.toBeNull();
    const icons = [...drawn.target.querySelectorAll(".fc-icon")];
    expect(icons.length).toBeGreaterThan(0);
    expect(icons.map((icon) => icon.getAttribute("aria-hidden"))).toEqual(
      icons.map(() => "true"),
    );
  });

  it("keeps the page language when a calendar passes its own", () => {
    drawn = draw("fr", { locale: "en", viewDidMount: () => {} });

    expect(drawn.name("prev")).toBe("Précédent");
    expect(
      drawn.target.querySelector(".fc-icon").getAttribute("aria-hidden"),
    ).toBe("true");
  });
});
