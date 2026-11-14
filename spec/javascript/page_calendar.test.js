// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import listPlugin from "@fullcalendar/list";

import { pageCalendar } from "../../app/javascript/src/page_calendar.js";

// The real FullCalendar, drawn on a page of the given language with the
// toolbar the staff calendars use.
function draw(lang, options = {}, ...plugins) {
  document.body.innerHTML = `<div id="cal"><p id="stale">old</p></div>`;
  document.documentElement.setAttribute("lang", lang);
  const target = document.getElementById("cal");
  const calendar = pageCalendar(
    target,
    {
      initialView: "timeGridWeek",
      headerToolbar: {
        left: "prev,next,today",
        center: "title",
        right: "timeGridWeek,dayGridMonth",
      },
      ...options,
    },
    ...plugins,
  );
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

  it("starts from the shared settings", () => {
    drawn = draw("en");

    expect(drawn.calendar.getOption("timeZone")).toBe("America/Toronto");
    expect(drawn.calendar.getOption("firstDay")).toBe(0);
    expect(drawn.calendar.getOption("height")).toBe("80vh");
    expect(drawn.calendar.getOption("scrollTime")).toBe("07:00:00");
  });

  it("lets the options change a shared setting, and adds the plugins given", () => {
    drawn = draw(
      "en",
      { timeZone: "America/New_York", height: "auto", initialView: "listWeek" },
      listPlugin,
    );

    expect(drawn.calendar.getOption("timeZone")).toBe("America/New_York");
    expect(drawn.calendar.getOption("height")).toBe("auto");
    expect(drawn.calendar.view.type).toBe("listWeek");
  });
});
