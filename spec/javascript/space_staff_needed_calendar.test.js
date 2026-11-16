// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";

await import("../../app/javascript/entrypoints/space_staff_needed_calendar.js");

const page = `
  <div id="link-container"></div>
  <button id="new-snc" type="button">New</button>
  <div id="new-link-input" style="visibility: hidden;">
    <input type="color" value="#123456">
    <input type="text" value="">
    <button class="snc-delete-button" type="button"></button>
  </div>`;

describe("space staff needed calendar entrypoint", () => {
  it("adds a visible row whose colour input keeps the template default and whose text inputs are empty", () => {
    document.body.innerHTML = page;
    document.dispatchEvent(new Event("DOMContentLoaded"));
    document.querySelector("#new-link-input input[type=text]").value = "typed";

    document.getElementById("new-snc").click();

    const row = document.querySelector("#link-container > div");
    expect(row.id).toBe("");
    expect(row.style.visibility).toBe("visible");
    expect(row.querySelector("input[type=color]").value).toBe("#123456");
    expect(row.querySelector("input[type=text]").value).toBe("");
  });
});
