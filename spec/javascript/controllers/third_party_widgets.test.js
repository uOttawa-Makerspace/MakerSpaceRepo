// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

let application;
let added = [];
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  delete window.turnstile;
  vi.restoreAllMocks();
});

async function mount(html) {
  // Capture the script tags instead of letting the DOM fetch them; each test fires the outcome by hand.
  added = [];
  vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
    added.push(node);
    return node;
  });
  vi.resetModules();
  const { default: Userway } =
    await import("../../../app/javascript/controllers/userway_controller.js");
  const { default: Turnstile } =
    await import("../../../app/javascript/controllers/turnstile_controller.js");
  document.body.innerHTML = html;
  application = Application.start();
  application.register("userway", Userway);
  application.register("turnstile", Turnstile);
  await settle();
}

const scripts = () => added;

describe("userway", () => {
  const html = `<div id="w" data-controller="userway" data-userway-src-value="https://cdn.example/widget-ok.js"
    data-userway-account-value="acct"></div>`;

  it("adds the vendor script with its account once the page has loaded", async () => {
    await mount(html);
    const [script] = scripts();
    expect(script.src).toBe("https://cdn.example/widget-ok.js");
    expect(script.getAttribute("data-account")).toBe("acct");
    script.dispatchEvent(new Event("load"));
    await settle();
    expect(document.getElementById("w").dataset.state).toBeUndefined();
  });

  it("leaves the page alone when the script cannot be loaded", async () => {
    await mount(html.replace("widget-ok", "widget-blocked"));
    scripts()[0].dispatchEvent(new Event("error"));
    await settle();
    expect(document.getElementById("w").dataset.state).toBe("unavailable");
  });

  it("waits for the window load event while the page is still loading", async () => {
    vi.spyOn(document, "readyState", "get").mockReturnValue("interactive");
    await mount(html.replace("widget-ok", "widget-late"));
    expect(scripts()).toHaveLength(0);
    window.dispatchEvent(new Event("load"));
    expect(scripts()).toHaveLength(1);
  });

  it("does not load when removed before the page finishes loading", async () => {
    vi.spyOn(document, "readyState", "get").mockReturnValue("interactive");
    await mount(html.replace("widget-ok", "widget-gone"));
    document.body.innerHTML = "";
    await settle();
    window.dispatchEvent(new Event("load"));
    expect(scripts()).toHaveLength(0);
  });
});

describe("userway across Turbo renders", () => {
  it("moves the vendor nodes into the incoming body and leaves other nodes", async () => {
    await mount(`<div id="w" data-controller="userway" data-userway-src-value="https://cdn.example/widget-turbo.js"
      data-action="turbo:before-render@document->userway#keepWidget"></div>
      <div class="userway_buttons_wrapper" id="vendor"></div><p id="page"></p>`);
    const newBody = document.createElement("body");
    document.dispatchEvent(
      new CustomEvent("turbo:before-render", { detail: { newBody } }),
    );
    expect(newBody.querySelectorAll(".userway_buttons_wrapper")).toHaveLength(
      1,
    );
    expect(newBody.querySelector("#vendor")).not.toBeNull();
    expect(newBody.querySelector("#page")).toBeNull();
    expect(newBody.querySelector("#w")).toBeNull();
  });
});

describe("userway on a cached restore", () => {
  it("replaces vendor nodes already in the incoming body with the live ones", async () => {
    await mount(`<div id="w" data-controller="userway" data-userway-src-value="https://cdn.example/widget-restore.js"></div>
      <div class="userway_buttons_wrapper" id="live"></div>`);
    const newBody = document.createElement("body");
    newBody.innerHTML =
      '<div class="userway_buttons_wrapper" id="dead"></div><p id="page"></p>';
    application
      .getControllerForElementAndIdentifier(
        document.getElementById("w"),
        "userway",
      )
      .keepWidget({
        detail: { newBody },
      });
    expect(newBody.querySelectorAll(".userway_buttons_wrapper")).toHaveLength(
      1,
    );
    expect(newBody.querySelector("#live")).not.toBeNull();
    expect(newBody.querySelector("#dead")).toBeNull();
    expect(newBody.querySelector("#page")).not.toBeNull();
  });
});

describe("turnstile", () => {
  const html = `<div id="t" class="cf-turnstile" data-controller="turnstile" data-sitekey="key123"
    data-turnstile-unavailable-message-value="Check unavailable"></div>`;

  it("renders the check into its element after the script loads", async () => {
    window.turnstile = { render: vi.fn() };
    await mount(html);
    scripts()[0].dispatchEvent(new Event("load"));
    await settle();
    expect(window.turnstile.render).toHaveBeenCalledWith(
      document.getElementById("t"),
      {
        sitekey: "key123",
      },
    );
  });

  it("renders one check after a disconnect and reconnect, removing the first", async () => {
    window.turnstile = {
      render: vi.fn().mockReturnValueOnce("id1").mockReturnValueOnce("id2"),
      remove: vi.fn(),
    };
    await mount(html);
    scripts()[0].dispatchEvent(new Event("load"));
    await settle();
    const element = document.getElementById("t");
    element.append(document.createElement("iframe"));
    element.dataset.controller = "";
    await settle();
    expect(window.turnstile.remove).toHaveBeenCalledWith("id1");
    // Turbo restoring a cached snapshot: the element comes back holding the old iframe.
    element.dataset.controller = "turnstile";
    await settle();
    scripts().at(-1).dispatchEvent(new Event("load"));
    await settle();
    expect(element.querySelectorAll("iframe")).toHaveLength(0);
    expect(window.turnstile.render).toHaveBeenCalledTimes(2);
  });

  it("shows a message in its element when the script cannot be loaded", async () => {
    await mount(html);
    scripts()[0].dispatchEvent(new Event("error"));
    await settle();
    const alert = document.querySelector("#t [role=alert]");
    expect(alert.textContent).toBe("Check unavailable");
  });

  it("shows no message when the element left the page before the failure", async () => {
    await mount(html);
    const script = scripts()[0];
    document.body.innerHTML = "";
    script.dispatchEvent(new Event("error"));
    await settle();
    expect(document.querySelector("[role=alert]")).toBeNull();
  });

  it("does not render into an element that left the page", async () => {
    window.turnstile = { render: vi.fn() };
    await mount(html);
    const script = scripts()[0];
    document.body.innerHTML = "";
    script.dispatchEvent(new Event("load"));
    await settle();
    expect(window.turnstile.render).not.toHaveBeenCalled();
  });
});
