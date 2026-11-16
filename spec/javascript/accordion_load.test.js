// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";

await import("../../app/javascript/src/accordion-load.js");

const PAGE = `
<button id="open-btn" data-bs-toggle="collapse" data-bs-target="#open-panel" aria-expanded="false"></button>
<div id="open-panel" class="collapse"></div>
<button id="shut-btn" data-bs-toggle="collapse" data-bs-target="#shut-panel" aria-expanded="true"></button>
<div id="shut-panel" class="collapse show"></div>`;

const load = () => document.dispatchEvent(new Event("turbo:load"));

describe("accordion state restore", () => {
  beforeEach(() => {
    localStorage.clear();
    document.body.innerHTML = PAGE;
  });

  it("opens a stored-open panel and sets aria-expanded on its trigger", () => {
    localStorage.setItem(
      location.pathname,
      JSON.stringify({ "open-panel": true }),
    );
    load();
    expect(
      document.getElementById("open-panel").classList.contains("show"),
    ).toBe(true);
    expect(
      document.getElementById("open-btn").getAttribute("aria-expanded"),
    ).toBe("true");
  });

  it("closes a stored-closed panel and sets aria-expanded to false", () => {
    localStorage.setItem(
      location.pathname,
      JSON.stringify({ "shut-panel": false }),
    );
    load();
    expect(
      document.getElementById("shut-panel").classList.contains("show"),
    ).toBe(false);
    expect(
      document.getElementById("shut-btn").getAttribute("aria-expanded"),
    ).toBe("false");
  });

  it("ignores stored panels missing from the page and unparsable storage", () => {
    localStorage.setItem(location.pathname, JSON.stringify({ gone: true }));
    expect(load).not.toThrow();
    localStorage.setItem(location.pathname, "{not json");
    expect(load).not.toThrow();
    expect(
      document.getElementById("open-btn").getAttribute("aria-expanded"),
    ).toBe("false");
  });
});
