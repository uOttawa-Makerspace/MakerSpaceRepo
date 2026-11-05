// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@fullcalendar/core", () => ({ Calendar: class {} }));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("tom-select", () => ({ default: class {} }));
vi.mock("flatpickr", () => ({ default: {} }));
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

const TABS = `
<ul>
  <button class="nav-link tab-link active" id="booking-calendar-tab-btn" data-bs-target="#booking-calendar-tab"></button>
  <button class="nav-link tab-link" id="booking-tab-btn" data-bs-target="#booking-tab"></button>
  <button class="nav-link tab-link" id="booking-admin-tab-btn" data-bs-target="#booking-admin-tab"></button>
</ul>
<div class="tab-pane active show" id="booking-calendar-tab"></div>
<div class="tab-pane" id="booking-tab"></div>
<div class="tab-pane" id="booking-admin-tab"><div id="pendingBody"></div><div id="approvedBody"></div></div>`;

async function load(url) {
  window.happyDOM.setURL(url);
  document.body.innerHTML = TABS;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/sub_space_booking.js");
}

const active = () =>
  [...document.querySelectorAll(".tab-pane.active")].map((e) => e.id);
const activeButtons = () =>
  [...document.querySelectorAll(".nav-link.active")].map((e) => e.id);

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
  window.scrollBy = vi.fn();
});

describe("tab routing", () => {
  it("shows the calendar tab when the address names nothing", async () => {
    await load("http://localhost/sub_space_booking?room=1");
    expect(active()).toEqual(["booking-calendar-tab"]);
    expect(activeButtons()).toEqual(["booking-calendar-tab-btn"]);
  });

  it("shows the tab named by the anchor", async () => {
    await load("http://localhost/sub_space_booking#booking-tab");
    expect(active()).toEqual(["booking-tab"]);
    expect(activeButtons()).toEqual(["booking-tab-btn"]);
    expect(
      document.getElementById("booking-tab").classList.contains("show"),
    ).toBe(true);
  });

  it("shows the admin tab and scrolls to the table of a page parameter", async () => {
    await load("http://localhost/sub_space_booking?approved_page=2");
    expect(active()).toEqual(["booking-admin-tab"]);
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
    expect(window.scrollBy).toHaveBeenCalled();
  });

  it("lets the anchor win over a page parameter", async () => {
    await load(
      "http://localhost/sub_space_booking?approved_page=2#booking-tab",
    );
    expect(active()).toEqual(["booking-tab"]);
  });

  it("ignores an anchor that names no tab", async () => {
    await load("http://localhost/sub_space_booking#nowhere");
    expect(active()).toEqual(["booking-calendar-tab"]);
  });

  it("switches tab when a tab button is clicked", async () => {
    await load("http://localhost/sub_space_booking");
    document.getElementById("booking-admin-tab-btn").click();
    expect(active()).toEqual(["booking-admin-tab"]);
    expect(activeButtons()).toEqual(["booking-admin-tab-btn"]);
  });

  it("re-reads the address after a Turbo render", async () => {
    await load("http://localhost/sub_space_booking");
    window.happyDOM.setURL("http://localhost/sub_space_booking#booking-tab");
    document.dispatchEvent(new Event("turbo:render"));
    expect(active()).toEqual(["booking-tab"]);
  });
});
