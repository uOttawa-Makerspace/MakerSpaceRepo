// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const { validation, validation_proposal, scrollToError } =
  await import("../../app/javascript/src/validation.js");

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
    expect(window.validation_proposal).toBe(validation_proposal);
    expect(window.scrollToError).toBe(scrollToError);
    expect(window.scrow_to_error).toBe(scrollToError);
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

describe("validation_proposal", () => {
  const page = (overrides = {}) => {
    const v = {
      username: "Ann",
      email: "a@b.c",
      client: "Acme",
      title: "A Title",
      background: "Some text",
      description: "Words",
      ...overrides,
    };
    document.body.innerHTML = `
      <input id="project_proposal_username" value="${v.username}">
      <input id="project_proposal_email" value="${v.email}">
      <input id="project_proposal_client" value="${v.client}">
      <input id="project_proposal_title" value="${v.title}">
      <input id="client_background_trix_input_project_proposal" value="${v.background}">
      <div id="trix_editor">${v.description}</div>`;
  };

  it("accepts a complete proposal", () => {
    page();
    expect(validation_proposal()).toBe(true);
    expect(errors()).toEqual([]);
  });

  it.each([
    ["username", "Your name is required", "project_proposal_username"],
    ["email", "Your email is required", "project_proposal_email"],
    ["client", "Client is required", "project_proposal_client"],
    ["title", "Project title is required.", "project_proposal_title"],
    [
      "background",
      "Client background is required.",
      "project_proposal_client_background",
    ],
    ["description", "Description is required.", "trix_editor"],
  ])("requires the %s", (field, message) => {
    page({ [field]: "  " });
    expect(validation_proposal()).toBe(false);
    expect(errors()).toEqual([message]);
  });

  it("scrolls to the first problem only", () => {
    page({ username: "", email: "" });
    expect(validation_proposal()).toBe(false);
    expect(errors()).toEqual(["Your name is required"]);
  });

  it("rejects punctuation in the title", () => {
    page({ title: "No $ign" });
    expect(validation_proposal()).toBe(false);
    expect(errors()).toEqual([
      "Project title may only contain letters and numbers.",
    ]);
  });

  it("passes on a page with none of the fields", () => {
    expect(validation_proposal()).toBe(true);
  });

  it.each([
    ["username", "project_proposal_username"],
    ["email", "project_proposal_email"],
    ["client", "project_proposal_client"],
    ["title", "project_proposal_title"],
    ["description", "trix_editor"],
  ])(
    "puts the %s message just before the field and scrolls to it",
    (field, id) => {
      page({ [field]: "" });
      const target = document.getElementById(id);
      target.getBoundingClientRect = () => ({ top: 400 });
      validation_proposal();
      expect(target.previousElementSibling.textContent).not.toBe("");
      expect(target.previousElementSibling.className).toBe(
        "form-error repo-form",
      );
      expect(window.scrollTo).toHaveBeenCalledTimes(1);
      expect(window.scrollTo).toHaveBeenCalledWith({
        top: 230,
        behavior: "smooth",
      });
    },
  );

  it("does not scroll for a missing client background, as its scroll target has another id", () => {
    page({ background: "" });
    expect(validation_proposal()).toBe(false);
    const field = document.getElementById(
      "client_background_trix_input_project_proposal",
    );
    expect(field.previousElementSibling.textContent).toBe(
      "Client background is required.",
    );
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it("scrolls for a missing client background when an element has the scroll id", () => {
    page({ background: "" });
    document.body.insertAdjacentHTML(
      "beforeend",
      '<div id="project_proposal_client_background"></div>',
    );
    validation_proposal();
    expect(window.scrollTo).toHaveBeenCalledTimes(1);
  });

  it("scrolls to the title when it has punctuation", () => {
    page({ title: "Bad!" });
    validation_proposal();
    expect(
      document.getElementById("project_proposal_title").previousElementSibling
        .textContent,
    ).toBe("Project title may only contain letters and numbers.");
    expect(window.scrollTo).toHaveBeenCalledTimes(1);
  });

  it("allows letters, digits, spaces and hyphens in the title, after trimming", () => {
    page({ title: "  Robot-Arm 2  " });
    expect(validation_proposal()).toBe(true);
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it("checks the fields in order: name, email, client, title, background, description", () => {
    const order = [
      ["username", "Your name is required"],
      ["email", "Your email is required"],
      ["client", "Client is required"],
      ["title", "Project title is required."],
      ["background", "Client background is required."],
      ["description", "Description is required."],
    ];
    order.forEach(([, message], i) => {
      const blanks = Object.fromEntries(order.slice(i).map(([f]) => [f, ""]));
      page(blanks);
      expect(validation_proposal()).toBe(false);
      expect(errors()).toEqual([message]);
    });
  });

  it.each([
    ["username", "#project_proposal_username"],
    ["email", "#project_proposal_email"],
    ["client", "#project_proposal_client"],
    ["title", "#project_proposal_title"],
    ["background", "#client_background_trix_input_project_proposal"],
    ["description", "#trix_editor"],
  ])(
    "skips the %s check when the field is not on the page",
    (field, selector) => {
      page({ [field]: "" });
      document.querySelector(selector).remove();
      expect(validation_proposal()).toBe(true);
      expect(errors()).toEqual([]);
    },
  );

  it("only checks the name, email, client and title when they are inputs", () => {
    page({ username: "", email: "", client: "", title: "" });
    for (const id of [
      "project_proposal_username",
      "project_proposal_email",
      "project_proposal_client",
      "project_proposal_title",
    ]) {
      document.getElementById(id).outerHTML =
        `<textarea id="${id}"></textarea>`;
    }
    expect(validation_proposal()).toBe(true);
  });

  it("reads the description from the editor's text, ignoring markup", () => {
    page({ description: "<div><br></div>" });
    expect(validation_proposal()).toBe(false);
    expect(errors()).toEqual(["Description is required."]);
    page({ description: "<div><strong>Hi</strong></div>" });
    expect(validation_proposal()).toBe(true);
  });

  it("clears every earlier form message, including the repository form's", () => {
    page();
    document.body.insertAdjacentHTML(
      "afterbegin",
      '<span class="form-error repo-form">old</span><span class="form-error">kept</span>',
    );
    expect(validation_proposal()).toBe(true);
    expect(errors()).toEqual([]);
    expect(document.querySelector("span.form-error").textContent).toBe("kept");
  });
});
