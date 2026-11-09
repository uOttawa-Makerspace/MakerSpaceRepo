// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      this.cleared = 0;
      this.optionsCleared = 0;
      this.synced = 0;
      el.tomselect = this;
      selects.push(this);
    }
    clear() {
      this.cleared++;
    }
    clearOptions() {
      this.optionsCleared++;
    }
    sync() {
      this.synced++;
    }
  },
}));
const toasts = vi.hoisted(() => []);
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));
vi.mock("../../../app/javascript/src/csrf", () => ({
  csrfHeaders: (headers) => ({ ...headers, "X-CSRF-Token": "tok" }),
}));

await import("../../../app/javascript/entrypoints/users.js");

const $ = (id) => document.getElementById(id);
const load = (html, hash = "") => {
  window.happyDOM.setURL(`http://localhost/users/ann${hash}`);
  document.body.innerHTML = html;
  selects.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
};

// the page script reads these on every load
const BASE = '<div id="staff-space-changer"></div>';

beforeEach(() => {
  vi.spyOn(console, "log").mockImplementation(() => {});
});

describe("profile tabs", () => {
  const tabs = (admin) => `
    <ul id="myTab">
      <a class="nav-link" id="t-info" href="#info"></a>
      <a class="nav-link" id="t-badges" href="#badges"></a>
      ${admin ? '<a class="nav-link" id="admin-tab" href="#admin"></a>' : ""}
    </ul>
    ${admin ? '<div id="adminTabPane"><a class="nav-link" id="a-roles" href="#admin-roles"></a><a class="nav-link" id="a-keys" href="#admin-keys"></a></div>' : ""}
    ${BASE}`;

  it("opens the tab named by the address", () => {
    const clicked = [];
    document.addEventListener("click", (e) => clicked.push(e.target.id), {
      capture: true,
    });
    load(tabs(false), "#badges");
    expect(clicked).toContain("t-badges");
    expect(clicked).not.toContain("t-info");
  });

  it("puts the tab in the address when it is clicked", () => {
    load(tabs(false));
    $("t-badges").click();
    expect(window.location.hash).toBe("#badges");
  });

  it("opens the admin tab and keeps the admin sub tab for an admin address", () => {
    const clicked = [];
    document.addEventListener("click", (e) => clicked.push(e.target.id), {
      capture: true,
    });
    load(tabs(true), "#admin-keys");
    expect(clicked).toContain("a-keys");
    expect(clicked).toContain("admin-tab");
    expect(window.location.hash).toBe("#admin-keys");
  });

  it("puts an admin sub tab in the address when it is clicked", () => {
    load(tabs(true));
    $("a-roles").click();
    expect(window.location.hash).toBe("#admin-roles");
  });

  it("ignores an admin address for someone without the admin tab", () => {
    load(tabs(false), "#admin-keys");
    expect(window.location.hash).toBe("#admin-keys");
  });

  it("puts the address back after a form submit reloads the page", () => {
    window.happyDOM.setURL("http://localhost/users/ann#badges");
    document.dispatchEvent(new Event("turbo:submit-start"));
    load(BASE);
    expect(window.location.hash).toBe("#badges");
  });
});

describe("show and hide controls", () => {
  it("shows and enables its target when a show control is checked", () => {
    load(
      `${BASE}<input type="radio" id="r" data-show="#extra"><div id="extra" style="display:none"></div>`,
    );
    $("r").checked = true;
    $("r").dispatchEvent(new Event("change"));
    expect($("extra").style.display).toBe("block");
    expect($("extra").disabled).toBe(false);
  });

  it("hides and disables its target when a hide control is checked", () => {
    load(
      `${BASE}<input type="radio" id="r" data-hide="#extra"><input id="extra">`,
    );
    $("r").checked = true;
    $("r").dispatchEvent(new Event("change"));
    expect($("extra").style.display).toBe("none");
    expect($("extra").disabled).toBe(true);
  });

  it("applies an already checked control at once", () => {
    load(
      `${BASE}<input type="radio" id="r" data-hide="#extra" checked><input id="extra">`,
    );
    expect($("extra").style.display).toBe("none");
  });

  it("does nothing while unchecked", () => {
    load(
      `${BASE}<input type="radio" id="r" data-hide="#extra"><input id="extra">`,
    );
    $("r").dispatchEvent(new Event("change"));
    expect($("extra").style.display).toBe("");
  });
});

describe("faculty and program", () => {
  const page = `${BASE}
    <select id="user_faculty"><option value="Eng">Eng</option><option value="Sci">Sci</option></select>
    <select id="user_program">
      <optgroup label="Eng"><option>Civil</option></optgroup>
      <optgroup label="Sci"><option>Physics</option></optgroup>
    </select>`;

  it("decorates the program select once", () => {
    load(page);
    expect(selects).toHaveLength(1);
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(1);
  });

  it("offers only the programs of the chosen faculty", () => {
    load(page);
    $("user_faculty").value = "Sci";
    $("user_faculty").dispatchEvent(new Event("change"));
    const groups = [...$("user_program").querySelectorAll("optgroup")];
    expect(groups.map((g) => g.label)).toEqual(["Sci"]);
    expect(selects[0].cleared).toBe(1);
    expect(selects[0].optionsCleared).toBe(1);
    expect(selects[0].synced).toBe(1);
  });

  it("works without a faculty select", () => {
    load(`${BASE}<select id="user_program"></select>`);
    expect(selects).toHaveLength(1);
  });
});

describe("role buttons", () => {
  it("hides the space changer for a regular user and shows it otherwise", () => {
    load(`<button class="role-button" id="a" value="regular_user"></button>
      <button class="role-button" id="b" value="staff"></button>${BASE}`);
    $("a").click();
    expect($("staff-space-changer").style.display).toBe("none");
    $("b").click();
    expect($("staff-space-changer").style.display).toBe("block");
  });
});

describe("key certificate upload", () => {
  const page = `${BASE}
    <form id="cert_form" action="/users/ann/cert"></form>
    <input type="file" class="key-cert-file" id="cert">
    <span id="cert_show"></span><span id="cert_hide" style="display:none"></span>`;

  const choose = (file) => {
    Object.defineProperty($("cert"), "files", {
      value: [file],
      configurable: true,
    });
    $("cert").dispatchEvent(new Event("change"));
  };
  const pdf = new File(["x"], "a.pdf", { type: "application/pdf" });

  it("uploads a PDF and swaps the prompt for the confirmation", async () => {
    load(page);
    const fetchMock = vi.fn(async () => ({ ok: true, text: async () => "{}" }));
    vi.stubGlobal("fetch", fetchMock);
    choose(pdf);
    await vi.waitFor(() => expect($("cert_show").style.display).toBe("none"));

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/users/ann/cert");
    expect(init.method).toBe("PATCH");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(init.body.get("cert").name).toBe("a.pdf");
    expect($("cert_hide").style.display).toBe("block");
  });

  it("keeps the prompt when the upload is refused", async () => {
    load(page);
    vi.stubGlobal("fetch", async () => ({ ok: false, text: async () => "" }));
    choose(pdf);
    await new Promise((r) => setTimeout(r, 0));
    expect($("cert_show").style.display).toBe("");
  });

  it("asks for a PDF when another kind of file is chosen", () => {
    load(page);
    const alertMock = vi.fn();
    vi.stubGlobal("alert", alertMock);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    choose({ name: "a.png", type: "image/png" });
    expect(alertMock).toHaveBeenCalledWith("Please attach a pdf file only");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("tells the user when the upload cannot be sent", async () => {
    load(page);
    document.documentElement.dataset.requestNetwork = "Server unreachable";
    toasts.length = 0;
    vi.stubGlobal("fetch", () => Promise.reject(new Error("offline")));
    choose(pdf);
    await vi.waitFor(() =>
      expect(toasts).toEqual([
        { message: "Server unreachable", type: "error" },
      ]),
    );
  });
});

describe("role spaces", () => {
  it("decorates each role space select with checkboxes", () => {
    load(
      `${BASE}<select class="role-space-select"></select><select class="role-space-select"></select>`,
    );
    expect(selects).toHaveLength(2);
    expect(selects[0].config.plugins.remove_button.title).toBe("Remove space");
  });

  it("saves the checked spaces of a user as they change", () => {
    load(`${BASE}<div>
      <input type="checkbox" class="set-user-space-button" id="s1" data-user-id="9" data-space-id="1" checked>
      <input type="checkbox" class="set-user-space-button" id="s2" data-user-id="9" data-space-id="2">
      <input type="checkbox" class="set-user-space-button" id="s3" data-user-id="9" data-space-id="3" checked>
    </div>`);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    $("s2").checked = true;
    $("s2").dispatchEvent(new Event("change"));

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/admin/users/set_role/");
    expect(init.method).toBe("PATCH");
    expect(JSON.parse(init.body)).toEqual({
      user_ids: ["9"],
      spaces: { 9: ["1", "2", "3"] },
    });
  });
});
