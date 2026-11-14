// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import listPlugin from "@fullcalendar/list";

import {
  calendarTexts,
  pageCalendar,
  relabel,
} from "../../app/javascript/src/page_calendar.js";
import {
  CALENDAR_TEXTS,
  textsAttribute,
} from "./calendars/calendar_texts_fixture.js";

// The real FullCalendar, drawn on a page of the given language with the
// toolbar the staff calendars use.
function draw(lang, options = {}, ...plugins) {
  document.body.innerHTML = `<div id="cal" ${textsAttribute(lang)}><p id="stale">old</p></div>`;
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

  it("reads the words the page gives its calendar element", () => {
    drawn = draw("fr");

    expect(calendarTexts(drawn.target)).toEqual(CALENDAR_TEXTS.fr);
  });

  it("gives FullCalendar the page's hints, in English and in French", () => {
    for (const [lang, close, link] of [
      ["en", "Close", "Go to March 17, 2027"],
      ["fr", "Fermer", "Aller au 17 mars 2027"],
    ]) {
      drawn?.calendar.destroy();
      drawn = draw(lang, { initialDate: "2027-03-17", navLinks: true });
      const header = drawn.target.querySelector(
        ".fc-col-header-cell[data-date='2027-03-17'] [data-navlink]",
      );

      expect(header.title).toBe(link);
      expect(drawn.calendar.getOption("closeHint")).toBe(close);
      expect(drawn.calendar.getOption("timeHint")).toBe(
        CALENDAR_TEXTS[lang].hints.timeHint,
      );
      expect(drawn.calendar.getOption("eventHint")).toBe(
        CALENDAR_TEXTS[lang].hints.eventHint,
      );
    }
  });

  it("names the buttons of a view of a few days only with the hints given", () => {
    const options = {
      initialView: "timeGridTwoDay",
      views: { timeGridTwoDay: { type: "timeGrid", duration: { days: 2 } } },
      headerToolbar: { left: "prev", center: "title", right: "next" },
    };
    drawn = draw("en", options);
    expect(drawn.name("prev")).toBe("Previous ");
    drawn.calendar.destroy();

    drawn = draw("en", {
      ...options,
      buttonHints: CALENDAR_TEXTS.en.daysButtonHints,
    });
    expect(drawn.name("prev")).toBe("Previous days");
    expect(drawn.name("next")).toBe("Next days");
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

  it("relabels a custom button, which is named after its new label and keeps it when the toolbar is drawn again", () => {
    drawn = draw("en", {
      headerToolbar: { left: "toggle,next", center: "title", right: "" },
      customButtons: { toggle: { text: "Show Weekends", click: () => {} } },
    });
    const button = () => drawn.target.querySelector(".fc-toggle-button");
    expect(button().title).toBe("Show Weekends");

    relabel(drawn.calendar, "toggle", "Hide Weekends");
    drawn.calendar.next();

    expect(button().textContent).toBe("Hide Weekends");
    expect(button().title).toBe("Hide Weekends");
    expect(drawn.calendar.getOption("customButtons").toggle.click).toBeTypeOf(
      "function",
    );
  });

  describe("the shared overlap toggle", () => {
    afterEach(() => localStorage.clear());

    const withToggle = (lang) =>
      draw(lang, {
        headerToolbar: { left: "toggleEventOverlap", center: "", right: "" },
      });
    const button = () =>
      drawn.target.querySelector(".fc-toggleEventOverlap-button");

    it("starts off, named for turning overlap on, until the browser remembers it on", () => {
      drawn = withToggle("en");
      expect(drawn.calendar.getOption("slotEventOverlap")).toBe(false);
      expect(button().title).toBe("Enable Event Overlap");
      drawn.calendar.destroy();

      localStorage.fullCalendarEventOverlap = "true";
      drawn = withToggle("fr");
      expect(drawn.calendar.getOption("slotEventOverlap")).toBe(true);
      expect(button().textContent).toBe(
        "Désactiver le chevauchement des événements",
      );
    });

    it("turns overlap the other way, remembers it and relabels its button", () => {
      drawn = withToggle("en");

      button().click();
      expect(drawn.calendar.getOption("slotEventOverlap")).toBe(true);
      expect(localStorage.fullCalendarEventOverlap).toBe("true");
      expect(button().title).toBe("Disable Event Overlap");

      button().click();
      expect(drawn.calendar.getOption("slotEventOverlap")).toBe(false);
      expect(localStorage.fullCalendarEventOverlap).toBe("false");
      expect(button().textContent).toBe("Enable Event Overlap");
    });

    it("is left out of a toolbar that only shows a button with a longer name", () => {
      drawn = draw("en", {
        headerToolbar: { left: "prev toggleEventOverlapFoo", right: "" },
        customButtons: { toggleEventOverlapFoo: { text: "Foo", click() {} } },
      });

      expect(drawn.calendar.getOption("slotEventOverlap")).toBeUndefined();
      expect(Object.keys(drawn.calendar.getOption("customButtons"))).toEqual([
        "toggleEventOverlapFoo",
      ]);
    });

    it("is left out of a calendar whose toolbar does not show it", () => {
      localStorage.fullCalendarEventOverlap = "true";
      drawn = draw("en", {
        customButtons: { book: { text: "Book", click() {} } },
      });

      // FullCalendar's own default stands: no option is set.
      expect(drawn.calendar.getOption("slotEventOverlap")).toBeUndefined();
      expect(Object.keys(drawn.calendar.getOption("customButtons"))).toEqual([
        "book",
      ]);
      localStorage.removeItem("fullCalendarEventOverlap");
      drawn.calendar.destroy();
      drawn = draw("en", { slotEventOverlap: false });
      expect(drawn.calendar.getOption("slotEventOverlap")).toBe(false);
    });
  });
});
