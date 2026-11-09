// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";

await import("../../../app/javascript/entrypoints/job_orders_wizard.js");

const $ = (id) => document.getElementById(id);
const ready = (html) => {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("DOMContentLoaded"));
};

const filesPage = (required) => `
  <div id="file-input-container">
    <div class="upload-file-input"><input type="file" ${required ? "required" : ""}><button class="delete-file-button" type="button"></button></div>
  </div>
  <div id="new-file-input" class="upload-file-input" style="display:none">
    <input type="file" required multiple><button class="delete-file-button" type="button"></button>
  </div>
  <button id="add-file-button" type="button"></button>`;

const rows = () =>
  document.querySelectorAll("#file-input-container .upload-file-input");
const deleteButtons = () => [
  ...document.querySelectorAll("#file-input-container .delete-file-button"),
];

describe("file inputs", () => {
  it("hides the only delete button when a file is required", () => {
    ready(filesPage(true));
    expect(deleteButtons()[0].style.display).toBe("none");
  });

  it("shows the delete button when a file is optional", () => {
    ready(filesPage(false));
    expect(deleteButtons()[0].style.display).toBe("inline-block");
  });

  it("adds another optional single file input from the template", () => {
    ready(filesPage(true));
    $("add-file-button").click();

    expect(rows()).toHaveLength(2);
    const added = rows()[1];
    expect(added.hasAttribute("id")).toBe(false);
    expect(added.style.display).toBe("flex");
    const input = added.querySelector("input");
    expect(input.required).toBe(false);
    expect(input.multiple).toBe(false);
    expect(deleteButtons().map((b) => b.style.display)).toEqual([
      "inline-block",
      "inline-block",
    ]);
  });

  it("removes an input again, but never the last required one", () => {
    ready(filesPage(true));
    $("add-file-button").click();
    deleteButtons()[1].click();
    expect(rows()).toHaveLength(1);

    deleteButtons()[0].click();
    expect(rows()).toHaveLength(1);
    expect(deleteButtons()[0].style.display).toBe("none");
  });

  it("lets an optional form remove every input", () => {
    ready(filesPage(false));
    deleteButtons()[0].click();
    expect(rows()).toHaveLength(0);
  });
});

describe("service selection", () => {
  const page = `
    <button class="accordion-button" data-service-group="print"><p class="text-muted">3D</p></button>
    <button class="accordion-button" data-service-group="laser"><p class="text-primary">Laser</p></button>
    <input type="radio" class="service-radio" name="s" value="print-a" data-service-group="print" id="print">
    <input type="radio" class="service-radio" name="s" value="laser-a" data-service-group="laser" id="laser">
    <input type="radio" class="service-radio" name="s" value="custom" data-service-group="custom" id="custom">
    <input class="service-name-field" data-service-group-id="print" value="ABS">
    <input class="service-name-field" data-service-group-id="laser" value="Wood">
    ${filesPage(false)}`;

  const header = (group) =>
    document.querySelector(`.accordion-button[data-service-group="${group}"]`);
  const select = (id) => {
    $(id).checked = true;
    $(id).dispatchEvent(new Event("change"));
  };

  it("highlights the header of the chosen service group only", () => {
    ready(page);
    select("print");
    expect(header("print").classList.contains("fw-bold")).toBe(true);
    expect(
      header("print").querySelector("p").classList.contains("text-primary"),
    ).toBe(true);
    expect(header("laser").classList.contains("fw-bold")).toBe(false);
    expect(
      header("laser").querySelector("p").classList.contains("text-muted"),
    ).toBe(true);

    select("laser");
    expect(header("print").classList.contains("fw-bold")).toBe(false);
    expect(header("laser").classList.contains("fw-bold")).toBe(true);
  });

  it("clears the other services' name fields for a custom request", () => {
    ready(page);
    select("custom");
    expect(
      [...document.querySelectorAll(".service-name-field")].map((f) => f.value),
    ).toEqual(["", ""]);
  });

  it("keeps the chosen service's own name field", () => {
    ready(
      page.replace('data-service-group="custom"', 'data-service-group="print"'),
    );
    select("custom");
    expect(
      [...document.querySelectorAll(".service-name-field")].map((f) => f.value),
    ).toEqual(["ABS", ""]);
  });

  it("highlights the service that starts out selected", () => {
    ready(page.replace('id="laser"', 'id="laser" checked'));
    expect(header("laser").classList.contains("fw-bold")).toBe(true);
    expect(header("print").classList.contains("fw-bold")).toBe(false);
  });

  it("copes with a selected service that has no header", () => {
    ready(page.replace('id="custom"', 'id="custom" checked'));
    expect(document.querySelectorAll(".fw-bold")).toHaveLength(0);
  });

  it("copes with a header that has no description", () => {
    ready(
      page
        .replace('<p class="text-muted">3D</p>', "")
        .replace('id="print"', 'id="print" checked'),
    );
    expect(header("print").classList.contains("fw-bold")).toBe(true);
    select("print");
    expect(header("print").classList.contains("fw-bold")).toBe(true);
  });
});
