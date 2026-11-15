// @vitest-environment happy-dom
import { Application } from "@hotwired/stimulus";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import BookingTabs from "../../../app/javascript/controllers/booking_tabs_controller.js";

const TABS = `
<div data-controller="booking-tabs">
  <div class="nav-link active" id="elsewhere"></div>
  <ul>
    <button class="nav-link tab-link active" id="booking-calendar-tab-btn" data-booking-tabs-target="tab" data-bs-target="#booking-calendar-tab"></button>
    <button class="nav-link tab-link" id="booking-tab-btn" data-booking-tabs-target="tab" data-bs-target="#booking-tab"></button>
    <button class="nav-link tab-link" id="booking-admin-tab-btn" data-booking-tabs-target="tab" data-bs-target="#booking-admin-tab"></button>
  </ul>
  <div class="tab-pane active show" id="booking-calendar-tab" data-booking-tabs-target="pane"></div>
  <div class="tab-pane fade" id="booking-tab" data-booking-tabs-target="pane"></div>
  <div class="tab-pane fade" id="booking-admin-tab" data-booking-tabs-target="pane"><div id="pendingBody"></div><div id="approvedBody"></div></div>
</div>`;

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function load(url, page = TABS) {
  window.happyDOM.setURL(url);
  document.body.innerHTML = page;
  await settle();
}

const active = () =>
  [...document.querySelectorAll(".tab-pane.active")].map((e) => e.id);
const shown = () =>
  [...document.querySelectorAll(".tab-pane.show")].map((e) => e.id);
const activeButtons = () =>
  [...document.querySelectorAll("button.nav-link.active")].map((e) => e.id);

beforeAll(() => {
  Application.start().register("booking-tabs", BookingTabs);
});

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
  window.scrollBy = vi.fn();
});

describe("booking tabs", () => {
  it("shows the calendar tab when the address names nothing", async () => {
    await load("http://localhost/sub_space_booking?room=1");
    expect(active()).toEqual(["booking-calendar-tab"]);
    expect(shown()).toEqual(["booking-calendar-tab"]);
    expect(activeButtons()).toEqual(["booking-calendar-tab-btn"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("shows the tab named by the anchor", async () => {
    await load("http://localhost/sub_space_booking#booking-tab");
    expect(active()).toEqual(["booking-tab"]);
    expect(shown()).toEqual(["booking-tab"]);
    expect(activeButtons()).toEqual(["booking-tab-btn"]);
  });

  it("shows the admin tab and scrolls to the table of a page parameter", async () => {
    await load("http://localhost/sub_space_booking?approved_page=2");
    expect(active()).toEqual(["booking-admin-tab"]);
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledTimes(1);
    expect(
      vi.mocked(Element.prototype.scrollIntoView).mock.contexts[0].id,
    ).toBe("approvedBody");
    expect(window.scrollBy).toHaveBeenCalledWith(0, -7 * 16);
  });

  it("takes the first page parameter in table order", async () => {
    await load(
      "http://localhost/sub_space_booking?approved_page=2&pending_page=3",
    );
    expect(
      vi.mocked(Element.prototype.scrollIntoView).mock.contexts[0].id,
    ).toBe("pendingBody");
  });

  it("shows the admin tab without scrolling when the table is missing", async () => {
    await load("http://localhost/sub_space_booking?denied_page=2");
    expect(active()).toEqual(["booking-admin-tab"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
    expect(window.scrollBy).not.toHaveBeenCalled();
  });

  it("leaves the tabs as they are for a page parameter without an admin tab", async () => {
    const page = TABS.replace(
      /<div class="tab-pane fade" id="booking-admin-tab"[\s\S]*?<\/div><\/div>/,
      "",
    );
    await load("http://localhost/sub_space_booking?pending_page=2", page);
    expect(active()).toEqual(["booking-calendar-tab"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("lets the anchor win over a page parameter", async () => {
    await load(
      "http://localhost/sub_space_booking?approved_page=2#booking-tab",
    );
    expect(active()).toEqual(["booking-tab"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("ignores an anchor that names no tab", async () => {
    await load("http://localhost/sub_space_booking#nowhere");
    expect(active()).toEqual(["booking-calendar-tab"]);
  });

  it("ignores an anchor that names a pane whose button is missing", async () => {
    await load("http://localhost/sub_space_booking#pendingBody");
    expect(active()).toEqual(["booking-calendar-tab"]);
  });

  it("touches only its own tabs", async () => {
    await load("http://localhost/sub_space_booking#booking-tab");
    expect(document.getElementById("elsewhere").classList).toContain("active");
  });

  it("leaves tab clicks to Bootstrap", async () => {
    await load("http://localhost/sub_space_booking");
    document.getElementById("booking-admin-tab-btn").click();
    expect(active()).toEqual(["booking-calendar-tab"]);
  });

  it("reads the address again when Turbo renders the tabs again", async () => {
    await load("http://localhost/sub_space_booking");
    await load("http://localhost/sub_space_booking#booking-admin-tab");
    expect(active()).toEqual(["booking-admin-tab"]);
  });
});
