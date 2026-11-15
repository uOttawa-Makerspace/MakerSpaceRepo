// @vitest-environment happy-dom
import { Application } from "@hotwired/stimulus";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

// Bootstrap's Tab, recording the buttons it is asked to show; the browser
// specs check what Bootstrap then does with them.
const shownTabs = [];
vi.mock("bootstrap", () => ({
  Tab: {
    getOrCreateInstance: (tab) => ({ show: () => shownTabs.push(tab.id) }),
  },
}));

const { default: BookingTabs } =
  await import("../../../app/javascript/controllers/booking_tabs_controller.js");

const TABS = `
<div data-controller="booking-tabs">
  <ul class="nav nav-tabs" role="tablist">
    <li class="nav-item"><button class="nav-link active" id="booking-calendar-tab-btn" data-booking-tabs-target="tab" data-bs-toggle="tab" data-bs-target="#booking-calendar-tab" type="button" role="tab"></button></li>
    <li class="nav-item"><button class="nav-link" id="booking-tab-btn" data-booking-tabs-target="tab" data-bs-toggle="tab" data-bs-target="#booking-tab" type="button" role="tab"></button></li>
    <li class="nav-item"><button class="nav-link" id="booking-admin-tab-btn" data-booking-tabs-target="tab" data-bs-toggle="tab" data-bs-target="#booking-admin-tab" type="button" role="tab"></button></li>
  </ul>
  <div class="tab-pane fade active show" id="booking-calendar-tab" role="tabpanel"></div>
  <div class="tab-pane fade" id="booking-tab" role="tabpanel"></div>
  <div class="tab-pane fade" id="booking-admin-tab" role="tabpanel"><div id="pendingBody"></div><div id="approvedBody"></div></div>
</div>`;

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function load(url, page = TABS) {
  shownTabs.length = 0;
  window.happyDOM.setURL(url);
  document.body.innerHTML = page;
  await settle();
}

const opened = () => shownTabs;

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
    expect(opened()).toEqual(["booking-calendar-tab-btn"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("shows the tab named by the anchor", async () => {
    await load("http://localhost/sub_space_booking#booking-tab");
    expect(opened()).toEqual(["booking-tab-btn"]);
  });

  it("shows the admin tab and scrolls to the table of a page parameter", async () => {
    await load("http://localhost/sub_space_booking?approved_page=2");
    expect(opened()).toEqual(["booking-admin-tab-btn"]);
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
    expect(opened()).toEqual(["booking-admin-tab-btn"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
    expect(window.scrollBy).not.toHaveBeenCalled();
  });

  it("shows nothing for a page parameter without an admin tab", async () => {
    const page = TABS.replace(
      /<li class="nav-item"><button class="nav-link" id="booking-admin-tab-btn"[^\n]*\n/,
      "",
    );
    await load("http://localhost/sub_space_booking?pending_page=2", page);
    expect(opened()).toEqual([]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("lets the anchor win over a page parameter", async () => {
    await load(
      "http://localhost/sub_space_booking?approved_page=2#booking-tab",
    );
    expect(opened()).toEqual(["booking-tab-btn"]);
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  it("shows nothing for an anchor that names no tab", async () => {
    await load("http://localhost/sub_space_booking#nowhere");
    expect(opened()).toEqual([]);
  });

  it("shows nothing for an anchor that names a pane's content", async () => {
    await load("http://localhost/sub_space_booking#pendingBody");
    expect(opened()).toEqual([]);
  });

  it("reads the address again when Turbo renders the tabs again", async () => {
    await load("http://localhost/sub_space_booking");
    await load("http://localhost/sub_space_booking#booking-admin-tab");
    expect(opened()).toEqual(["booking-admin-tab-btn"]);
  });
});
