// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const modal = { show: vi.fn(), hide: vi.fn() };
vi.mock("bootstrap", () => ({
  Modal: { getOrCreateInstance: () => modal },
}));

const tables = new Set();
const redraws = [];
const destroys = [];
vi.mock("datatables.net-bs5", () => ({
  default: class {
    static isDataTable(el) {
      return tables.has(el);
    }
    constructor(el) {
      this.el = el;
    }
    draw() {
      redraws.push(this.el);
    }
    destroy() {
      destroys.push(this.el);
    }
  },
}));

let onMessage;
vi.mock("../../../app/javascript/channels/staff_dashboard_channel", () => ({
  staffDashboardChannelConnection: (callback) => (onMessage = callback),
}));

await import("../../../app/javascript/entrypoints/staff_dashboard.js");

const $ = (id) => document.getElementById(id);
const load = async (html) => {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("turbo:load"));
  await new Promise((r) => setTimeout(r, 0));
};

const MODAL = `
<div id="signinModal"></div>
<div id="outer-progress-bar"></div><div id="signin-progress-bar"></div>
<span id="sign-in-username"></span><a id="sign-in-profile-link"></a>
<span id="sign-in-email"></span>
<div id="no-membership"></div><div id="has-membership"></div><span id="sign-in-membership"></span>
<div id="not-student"></div><div id="is-student"></div>
<div id="unsigned-consent-form"></div><div id="signed-consent-form"></div>
<div id="sign-in-certifications"></div>`;

const member = {
  username: "ann",
  email: "ann@example.com",
  membership: true,
  expiration_date: "2027-01-01",
  is_student: true,
  signed_sheet: false,
  certification: ["Laser", "3D"],
};

beforeEach(() => {
  modal.show.mockClear();
  modal.hide.mockClear();
  tables.clear();
  redraws.length = 0;
  destroys.length = 0;
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, text: async () => "5 of 20" })),
  );
});

afterEach(() => vi.useRealTimers());

describe("capacity", () => {
  it("refreshes the capacity alert when the page loads", async () => {
    await load('<div class="max_capacity_alert">old</div>');
    expect(fetch).toHaveBeenCalledWith(
      "/staff_dashboard/refresh_capacity",
      expect.objectContaining({
        headers: expect.objectContaining({
          "X-Requested-With": "XMLHttpRequest",
        }),
      }),
    );
    expect(document.querySelector(".max_capacity_alert").innerHTML).toBe(
      "5 of 20",
    );
  });

  it("leaves the alert alone for a failed response", async () => {
    fetch.mockResolvedValue({ ok: false });
    await load('<div class="max_capacity_alert">old</div>');
    expect(document.querySelector(".max_capacity_alert").innerHTML).toBe("old");
  });

  it("logs a failed request", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    fetch.mockRejectedValue(new Error("offline"));
    await load('<div class="max_capacity_alert"></div>');
    expect(error).toHaveBeenCalledWith(
      "Failed to refresh capacity:",
      expect.any(Error),
    );
  });

  it("does not ask without the alert", async () => {
    await load("<p>x</p>");
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("excel upload label", () => {
  it("shows the chosen file name next to the input", async () => {
    await load(`<input class="form-control-input-excel" id="visible"><label id="name"></label>
      <input type="file" id="excel-input">`);
    Object.defineProperty($("excel-input"), "files", {
      value: [{ name: "staff.xlsx" }],
    });
    $("visible").dispatchEvent(new Event("change"));
    expect($("name").innerText).toBe("staff.xlsx");
  });

  it("changes nothing when no file is chosen", async () => {
    await load(`<input class="form-control-input-excel" id="visible"><label id="name">none</label>
      <input type="file" id="excel-input">`);
    $("visible").dispatchEvent(new Event("change"));
    expect($("name").innerText).toBe("none");
  });
});

describe("sign in notification", () => {
  const tapIn = (user = member) => onMessage({ add_user: user });

  it("ignores messages that are not a sign in", async () => {
    await load(MODAL);
    onMessage(undefined);
    onMessage({ other: 1 });
    expect(modal.show).not.toHaveBeenCalled();
  });

  it("shows who signed in, with membership, student and consent details", async () => {
    await load(MODAL);
    tapIn();
    expect($("sign-in-username").innerText).toBe("ann");
    expect($("sign-in-profile-link").getAttribute("href")).toBe("ann");
    expect($("sign-in-email").innerText).toBe("ann@example.com");
    expect($("sign-in-membership").innerText).toBe("Active until 2027-01-01");
    expect($("has-membership").style.display).toBe("block");
    expect($("no-membership").style.display).toBe("none");
    expect($("is-student").style.display).toBe("block");
    expect($("not-student").style.display).toBe("none");
    expect($("unsigned-consent-form").style.display).toBe("block");
    expect($("signed-consent-form").style.display).toBe("none");
    expect($("sign-in-certifications").textContent).toContain("Laser");
    expect(
      $("signin-progress-bar").classList.contains("moving-progress-bar"),
    ).toBe(true);
    expect(modal.show).toHaveBeenCalled();
  });

  it("copes with a person with few details", async () => {
    await load(MODAL);
    tapIn({ membership: false, signed_sheet: true, is_student: false });
    expect($("sign-in-username").innerText).toBe("");
    expect($("sign-in-profile-link").getAttribute("href")).toBe("#");
    expect($("no-membership").style.display).toBe("block");
    expect($("signed-consent-form").style.display).toBe("block");
    expect($("sign-in-membership").innerText).toBe("Active until ");
  });

  it("refreshes the signed in table", async () => {
    await load(`${MODAL}<table id="signed-in-table"></table>`);
    tables.add($("signed-in-table"));
    tapIn();
    expect(redraws).toEqual([$("signed-in-table")]);
  });

  it("does nothing when the page has no sign in dialog", async () => {
    await load("<p>x</p>");
    tapIn();
    expect(modal.show).not.toHaveBeenCalled();
  });

  it("stays quiet when notifications are switched off", async () => {
    await load(`${MODAL}<input type="checkbox" id="popup_enabled">`);
    tapIn();
    expect(modal.show).not.toHaveBeenCalled();
    $("popup_enabled").checked = true;
    tapIn();
    expect(modal.show).toHaveBeenCalledTimes(1);
  });

  it("stays quiet while the staff member is typing in the user search", async () => {
    await load(`${MODAL}<select id="user_dashboard_select"></select>`);
    $("user_dashboard_select").tomselect = {
      isOpen: true,
      inputValue: () => "an",
    };
    tapIn();
    expect(modal.show).not.toHaveBeenCalled();

    $("user_dashboard_select").tomselect.inputValue = () => "";
    tapIn();
    expect(modal.show).toHaveBeenCalledTimes(1);
  });

  it("hides itself after six seconds unless it was clicked", async () => {
    await load(MODAL);
    vi.useFakeTimers();
    tapIn();
    vi.advanceTimersByTime(5999);
    expect(modal.hide).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(modal.hide).toHaveBeenCalledTimes(1);

    tapIn();
    $("signinModal").click();
    expect(
      $("outer-progress-bar").classList.contains("fading-progress-bar"),
    ).toBe(true);
    vi.advanceTimersByTime(6000);
    expect(modal.hide).toHaveBeenCalledTimes(1);
  });

  it("restarts the timer for a second sign in", async () => {
    await load(MODAL);
    vi.useFakeTimers();
    tapIn();
    vi.advanceTimersByTime(4000);
    tapIn();
    vi.advanceTimersByTime(4000);
    expect(modal.hide).not.toHaveBeenCalled();
    vi.advanceTimersByTime(2000);
    expect(modal.hide).toHaveBeenCalledTimes(1);
  });

  it("clears the fading bar when the dialog closes", async () => {
    await load(MODAL);
    $("outer-progress-bar").classList.add("fading-progress-bar");
    $("signinModal").dispatchEvent(new Event("hidden.bs.modal"));
    expect(
      $("outer-progress-bar").classList.contains("fading-progress-bar"),
    ).toBe(false);
  });
});

describe("live table updates", () => {
  it("rebuilds the data tables around a stream render", async () => {
    document.body.innerHTML = '<table class="dataTable" id="t"></table>';
    tables.add($("t"));
    const original = vi.fn();
    const event = new Event("turbo:before-stream-render");
    event.detail = { render: original };
    document.dispatchEvent(event);

    event.detail.render("stream");
    expect(destroys).toEqual([$("t")]);
    expect(original).toHaveBeenCalledWith("stream");
  });

  it("only destroys tables that are data tables", async () => {
    document.body.innerHTML = '<table class="dataTable" id="t"></table>';
    const event = new Event("turbo:before-stream-render");
    event.detail = { render: vi.fn() };
    document.dispatchEvent(event);
    event.detail.render("stream");
    expect(destroys).toEqual([]);
  });
});
