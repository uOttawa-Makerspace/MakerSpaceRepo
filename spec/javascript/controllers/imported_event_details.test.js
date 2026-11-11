// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const shown = vi.fn();
vi.mock("bootstrap", () => ({
  Modal: {
    getOrCreateInstance: () => ({ show: shown }),
  },
}));

const { default: ImportedEventDetails } =
  await import("../../../app/javascript/controllers/imported_event_details_controller.js");

const PAGE = `
<div id="dialog" data-controller="imported-event-details" data-imported-event-details-from-value="Imported from a linked calendar ({host})." data-imported-event-details-all-day-value="All day" data-action="hidden.bs.modal->imported-event-details#returnFocus">
  <h5 data-imported-event-details-target="title"></h5>
  <p data-imported-event-details-target="time"></p>
  <p data-imported-event-details-target="description"></p>
  <p data-imported-event-details-target="source"></p>
</div>
<button id="opener"></button>`;

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
let application;

async function boot() {
  document.body.innerHTML = PAGE;
  application = Application.start();
  application.register("imported-event-details", ImportedEventDetails);
  await settle();
  return application.getControllerForElementAndIdentifier(
    document.getElementById("dialog"),
    "imported-event-details",
  );
}

const text = (target) =>
  document.querySelector(`[data-imported-event-details-target="${target}"]`)
    .textContent;

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  shown.mockClear();
});

describe("imported event details dialog", () => {
  it("shows the title, Toronto times, description and link host", async () => {
    const controller = await boot();
    controller.show({
      title: "Dentist",
      startStr: "2027-03-17T13:00:00-04:00",
      endStr: "2027-03-17T15:30:00-04:00",
      allDay: false,
      extendedProps: {
        sourceHost: "calendar.google.com",
        description: "Bring forms",
      },
    });
    expect(text("title")).toBe("Dentist");
    expect(text("time")).toContain("1:00");
    expect(text("time")).toContain("3:30");
    expect(text("time")).toContain("2027");
    expect(text("description")).toBe("Bring forms");
    expect(text("source")).toBe(
      "Imported from a linked calendar (calendar.google.com).",
    );
    expect(shown).toHaveBeenCalledTimes(1);
  });

  it("reads the time in Toronto whatever offset the string carries", async () => {
    const controller = await boot();
    controller.show({
      title: "Late",
      startStr: "2027-03-18T02:00:00Z",
      endStr: "",
      allDay: false,
      extendedProps: {},
    });
    expect(text("time")).toContain("Mar 17, 2027");
    expect(text("time")).toContain("10:00");
  });

  it("writes the title, description and host as text, never markup", async () => {
    const controller = await boot();
    controller.show({
      title: "<img src=x onerror=alert(1)>",
      startStr: "2027-03-17T13:00:00-04:00",
      endStr: "2027-03-17T14:00:00-04:00",
      allDay: false,
      extendedProps: {
        sourceHost: "<b>Cal</b>",
        description: "<script>alert(1)</script>",
      },
    });
    expect(
      document.querySelector("#dialog img, #dialog b, #dialog script"),
    ).toBeNull();
    expect(text("title")).toBe("<img src=x onerror=alert(1)>");
    expect(text("description")).toBe("<script>alert(1)</script>");
    expect(text("source")).toBe(
      "Imported from a linked calendar (<b>Cal</b>).",
    );
  });

  it("shows an all-day event as its days, with the last day inclusive", async () => {
    const controller = await boot();
    controller.show({
      title: "Holiday",
      startStr: "2027-03-17",
      endStr: "2027-03-19",
      allDay: true,
      extendedProps: {},
    });
    expect(text("time")).toBe("Mar 17, 2027 – Mar 18, 2027 · All day");
  });

  it("shows a single all-day event as one day and an empty description as nothing", async () => {
    const controller = await boot();
    controller.show({
      title: "Holiday",
      startStr: "2027-03-17",
      endStr: "2027-03-18",
      allDay: true,
      extendedProps: { description: null },
    });
    expect(text("time")).toBe("Mar 17, 2027 · All day");
    expect(text("description")).toBe("");
    expect(
      document.querySelector(
        '[data-imported-event-details-target="description"]',
      ).hidden,
    ).toBe(true);
  });

  it("shows a timed event ending on another day with both dates", async () => {
    const controller = await boot();
    controller.show({
      title: "Overnight",
      startStr: "2027-03-17T22:00:00-04:00",
      endStr: "2027-03-18T06:00:00-04:00",
      allDay: false,
      extendedProps: {},
    });
    expect(text("time")).toContain("Mar 17, 2027");
    expect(text("time")).toContain("Mar 18, 2027");
  });

  it("gives the focus back to the element that opened it when it closes", async () => {
    const controller = await boot();
    const opener = document.getElementById("opener");
    controller.show(
      {
        title: "x",
        startStr: "2027-03-17T13:00:00-04:00",
        endStr: "",
        allDay: false,
        extendedProps: {},
      },
      opener,
    );
    const spy = vi.spyOn(opener, "focus");
    document
      .getElementById("dialog")
      .dispatchEvent(new Event("hidden.bs.modal"));
    expect(spy).toHaveBeenCalledTimes(1);
    document
      .getElementById("dialog")
      .dispatchEvent(new Event("hidden.bs.modal"));
    expect(spy).toHaveBeenCalledTimes(1);
  });
});
