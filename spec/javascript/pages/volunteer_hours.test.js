// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";

await import("../../../app/javascript/entrypoints/volunteer_hours.js");

const formHtml = (hours, minutes, stored = "") => `
  <form class="needs-validation" novalidate>
    <input id="hours" type="number" required value="${hours}">
    <input id="minutes" type="number" required value="${minutes}">
    <input id="total_time_hidden" type="hidden" value="${stored}">
  </form>`;

const load = (html) => {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("turbo:load"));
  window.dispatchEvent(new Event("load"));
  return document.querySelector("form");
};

const submit = (form) => {
  const event = new Event("submit", { cancelable: true, bubbles: true });
  form.dispatchEvent(event);
  return event;
};

describe("volunteer hours form", () => {
  it("combines hours and minutes into decimal hours on submit", () => {
    const form = load(formHtml("2", "30"));
    const event = submit(form);
    expect(document.getElementById("total_time_hidden").value).toBe("2.5");
    expect(event.defaultPrevented).toBe(false);
    expect(form.classList.contains("was-validated")).toBe(true);
  });

  it("adds minutes to hours numerically", () => {
    load(formHtml("10", "15"));
    submit(document.querySelector("form"));
    expect(document.getElementById("total_time_hidden").value).toBe("10.25");
  });

  it("blocks the submit and leaves the total alone when the form is invalid", () => {
    const form = load(formHtml("", "30"));
    const event = submit(form);
    expect(event.defaultPrevented).toBe(true);
    expect(document.getElementById("total_time_hidden").value).toBe("");
    expect(form.classList.contains("was-validated")).toBe(true);
  });

  it("keeps the stored total when an edit leaves the boxes untouched", () => {
    load(formHtml("0", "20", "0.33"));
    submit(document.querySelector("form"));
    expect(document.getElementById("total_time_hidden").value).toBe("0.33");
  });

  it("recomputes the total when an edit changes a box", () => {
    load(formHtml("0", "20", "0.33"));
    document.getElementById("minutes").value = "30";
    submit(document.querySelector("form"));
    expect(document.getElementById("total_time_hidden").value).toBe("0.5");
  });
});
