// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const validationModule = await import("../../app/javascript/src/validation.js");
const { validation, scrollToError } = validationModule;

const errors = () =>
  [...document.querySelectorAll("span.form-error.repo-form")].map(
    (e) => e.textContent,
  );

beforeEach(() => {
  document.body.innerHTML = "";
  window.scrollTo = vi.fn();
});

describe("legacy globals", () => {
  it("exposes the validators for inline form handlers", () => {
    expect(window.validation).toBe(validation);
    expect(window.scrollToError).toBe(scrollToError);
    expect(window.scrow_to_error).toBe(scrollToError);
  });

  it("has no proposal form validator, which no page calls", () => {
    expect(window.validation_proposal).toBeUndefined();
    expect(validationModule.validation_proposal).toBeUndefined();
  });
});

describe("scrollToError", () => {
  it("scrolls smoothly to just above the element", () => {
    document.body.innerHTML = '<div id="x"></div>';
    scrollToError("x");
    expect(window.scrollTo).toHaveBeenCalledWith({
      top: -170,
      behavior: "smooth",
    });
  });

  it("does nothing for an unknown element", () => {
    scrollToError("missing");
    expect(window.scrollTo).not.toHaveBeenCalled();
  });
});

describe("validation (repository form)", () => {
  const form = (title, { photos = 0, container = true } = {}) => {
    document.body.innerHTML = `
      <input id="repository_title" value="${title}">
      <div id="image-container">${"<div></div>".repeat(photos)}</div>
      ${container ? '<div class="repo-image"></div>' : ""}`;
  };

  it("accepts a titled project with a photo", () => {
    form("My Robot 2", { photos: 1 });
    expect(validation()).toBe(true);
    expect(errors()).toEqual([]);
  });

  it("requires a title", () => {
    form("   ", { photos: 1 });
    expect(validation()).toBe(false);
    expect(errors()).toEqual(["Project title is required."]);
  });

  it("allows only letters, digits, spaces and hyphens in the title", () => {
    form("Robot!", { photos: 1 });
    expect(validation()).toBe(false);
    expect(errors()).toEqual([
      "Project title may only contain letters and numbers.",
    ]);
  });

  it("requires at least one photo in the image area", () => {
    form("Robot");
    expect(validation()).toBe(false);
    expect(errors()).toEqual(["At least one photo is required."]);

    form("Robot", { photos: 1 });
    expect(validation()).toBe(true);
  });

  it("does not ask for a photo on a form without the image area", () => {
    form("Robot", { container: false });
    expect(validation()).toBe(true);
  });

  it("clears the previous messages on each run", () => {
    form("", { photos: 1 });
    validation();
    validation();
    expect(errors()).toHaveLength(1);
  });

  it("passes on a page without a title field", () => {
    document.body.innerHTML = '<div id="image-container"><div></div></div>';
    expect(validation()).toBe(true);
  });
});
