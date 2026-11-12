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
