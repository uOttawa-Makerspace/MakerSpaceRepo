// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("printer_issues", () => {
  const FORM =
    '<input id="printer_issue_summary"><select id="printer_issue_printer_id"><option value="1">a</option><option value="2">b</option></select>';

  async function load(html) {
    document.body.innerHTML = html;
    vi.resetModules();
    await import("../../../app/javascript/entrypoints/printer_issues.js");
  }

  beforeEach(() => {
    globalThis.issueSummary = { 1: { "Nozzle clog": 1 } };
  });
  afterEach(() => {
    delete globalThis.issueSummary;
  });

  it("marks a summary that repeats an open issue of the chosen printer", async () => {
    await load(FORM);
    const input = document.querySelector("#printer_issue_summary");
    input.value = "the nozzle clog again";
    input.dispatchEvent(new Event("input"));
    expect(input.classList.contains("is-invalid")).toBe(true);
    input.value = "something else";
    input.dispatchEvent(new Event("input"));
    expect(input.classList.contains("is-invalid")).toBe(false);
    input.value = "nozzle clog";
    const select = document.querySelector("#printer_issue_printer_id");
    select.value = "2";
    select.dispatchEvent(new Event("input"));
    expect(input.classList.contains("is-invalid")).toBe(false);
  });

  it("binds nothing when the form is absent", async () => {
    await expect(load("<div></div>")).resolves.toBeUndefined();
  });

  it("binds nothing without the issue summary data", async () => {
    delete globalThis.issueSummary;
    await expect(load(FORM)).resolves.toBeUndefined();
  });
});
