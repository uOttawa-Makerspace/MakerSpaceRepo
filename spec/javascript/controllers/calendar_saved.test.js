// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application, Controller } from "@hotwired/stimulus";

const { default: CalendarSaved } =
  await import("../../../app/javascript/controllers/calendar_saved_controller.js");

const adminSaved = vi.fn();
const staffSaved = vi.fn();
class FakeAdmin extends Controller {
  saved() {
    adminSaved();
  }
}
class FakeStaff extends Controller {
  saved() {
    staffSaved();
  }
}

const MARKER = `<span id="marker" data-controller="calendar-saved"
  data-calendar-saved-admin-calendar-outlet="#admin_calendar"
  data-calendar-saved-unavailabilities-calendar-outlet="#unavailabilities_calendar"></span>`;

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function boot(calendar) {
  document.body.innerHTML = calendar + '<div id="flash"></div>';
  application = Application.start();
  application.register("admin-calendar", FakeAdmin);
  application.register("unavailabilities-calendar", FakeStaff);
  application.register("calendar-saved", CalendarSaved);
  await settle();
  document.getElementById("flash").insertAdjacentHTML("beforeend", MARKER);
  await settle();
}

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  vi.clearAllMocks();
});

describe("the calendar-saved marker", () => {
  it("tells the admin calendar and removes itself", async () => {
    await boot(
      '<div id="admin_calendar" data-controller="admin-calendar"></div>',
    );
    expect(adminSaved).toHaveBeenCalledTimes(1);
    expect(staffSaved).not.toHaveBeenCalled();
    expect(document.getElementById("marker")).toBeNull();
  });

  it("tells the unavailabilities calendar when the page has no admin calendar", async () => {
    await boot(
      '<div id="unavailabilities_calendar" data-controller="unavailabilities-calendar"></div>',
    );
    expect(staffSaved).toHaveBeenCalledTimes(1);
    expect(adminSaved).not.toHaveBeenCalled();
    expect(document.getElementById("marker")).toBeNull();
  });
});
