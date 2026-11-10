// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const { default: LearningModuleForm } =
  await import("../../../app/javascript/controllers/learning-module-form_controller.js");

let application;
const $ = (id) => document.getElementById(id);
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(html) {
  document.body.innerHTML = html;
  application = Application.start();
  application.register("learning-module-form", LearningModuleForm);
  await settle();
}

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  vi.useRealTimers();
});

const formHtml = ({ required = true, scorm = false } = {}) => `
  <form id="f" data-controller="learning-module-form"
        data-action="submit->learning-module-form#submit"
        data-learning-module-form-photos-required-value="${required}">
    <input type="checkbox" id="scorm" data-learning-module-form-target="scormToggle"
           data-action="change->learning-module-form#toggleScorm" ${scorm ? "checked" : ""}>
    <fieldset id="regular" data-learning-module-form-target="regularSection">
      <div class="image-item"><button type="button" id="rm-image" data-action="learning-module-form#removeImage"></button></div>
      <div class="video-item"><button type="button" id="rm-video" data-action="learning-module-form#removeVideo"></button></div>
      <div id="rows"><div class="input-group" id="row">
        <input type="file" id="learning_module_photos" data-learning-module-form-target="photos">
        <button type="button" id="new-photo-input" data-action="learning-module-form#addPhoto"><i class="fa fa-plus"></i></button>
      </div></div>
    </fieldset>
    <fieldset id="scorm-section" data-learning-module-form-target="scormSection"></fieldset>
    <button id="waiting-save-button" data-learning-module-form-target="saveButton">Save</button>
  </form>`;

const submit = () => {
  const event = new Event("submit", { cancelable: true, bubbles: true });
  $("f").dispatchEvent(event);
  return event;
};

describe("photo check", () => {
  it("asks for an image when none is chosen, once", async () => {
    await mount(formHtml());
    expect(submit().defaultPrevented).toBe(true);
    submit();
    expect($("learning_module_photos").classList.contains("is-invalid")).toBe(
      true,
    );
    expect(document.querySelectorAll(".invalid-feedback")).toHaveLength(1);
    expect(document.querySelector(".invalid-feedback").textContent).toBe(
      "You must upload at least one image",
    );
  });

  it("lets the form go with an image", async () => {
    await mount(formHtml());
    Object.defineProperty($("learning_module_photos"), "files", {
      value: [{}],
    });
    expect(submit().defaultPrevented).toBe(false);
  });

  it("is not asked for on edit", async () => {
    await mount(formHtml({ required: false }));
    expect(submit().defaultPrevented).toBe(false);
  });

  it("is not asked for a SCORM module, whose photos are not submitted", async () => {
    await mount(formHtml({ scorm: true }));
    expect(submit().defaultPrevented).toBe(false);
  });

  it("leaves the save button alone when the photo check refuses", async () => {
    await mount(formHtml());
    vi.useFakeTimers();
    submit();
    vi.advanceTimersByTime(0);
    expect($("waiting-save-button").disabled).toBe(false);
  });

  it("works for a form that appears after the page loaded", async () => {
    await mount("<p>index</p>");
    document.body.insertAdjacentHTML("beforeend", formHtml());
    await settle();
    expect(submit().defaultPrevented).toBe(true);
  });
});

describe("photo rows", () => {
  it("adds another photo row whose button removes it", async () => {
    await mount(formHtml());
    $("new-photo-input").click();
    const rows = document.querySelectorAll(".input-group");
    expect(rows).toHaveLength(2);
    const added = rows[1].querySelector("button");
    expect(added.id).toBe("");
    expect(added.className).toBe("btn btn-danger");
    expect(added.querySelector("i").className).toBe("fa fa-trash");
    expect(
      rows[1]
        .querySelector("input")
        .hasAttribute("data-learning-module-form-target"),
    ).toBe(false);
    await settle();
    added.click();
    expect(document.querySelectorAll(".input-group")).toHaveLength(1);
  });

  it("removes an image or a video item", async () => {
    await mount(formHtml());
    $("rm-image").click();
    $("rm-video").click();
    expect(document.querySelector(".image-item")).toBeNull();
    expect(document.querySelector(".video-item")).toBeNull();
  });
});

describe("scorm toggle", () => {
  it("shows the package fields for SCORM and the file fields otherwise", async () => {
    await mount(formHtml());
    expect($("scorm-section").disabled).toBe(true);
    expect($("scorm-section").style.display).toBe("none");
    expect($("regular").disabled).toBe(false);

    $("scorm").checked = true;
    $("scorm").dispatchEvent(new Event("change", { bubbles: true }));
    expect($("scorm-section").disabled).toBe(false);
    expect($("scorm-section").style.display).toBe("");
    expect($("regular").disabled).toBe(true);
    expect($("regular").style.display).toBe("none");
  });

  it("is skipped when the form has no toggle", async () => {
    await mount('<form id="f" data-controller="learning-module-form"></form>');
    expect($("f")).not.toBeNull();
  });
});

describe("save button", () => {
  const page = (extra = "") => `
    <form id="f" data-controller="learning-module-form"
          data-action="submit->learning-module-form#submit">
      <input required id="r" value="x">${extra}
    </form>`;
  const button =
    '<button id="waiting-save-button" data-learning-module-form-target="saveButton">Save</button>';

  it("shows a waiting message once a valid form is submitted", async () => {
    await mount(page(button));
    vi.useFakeTimers();
    submit();
    vi.advanceTimersByTime(0);
    expect($("waiting-save-button").disabled).toBe(true);
    expect($("waiting-save-button").innerHTML).toContain(
      "Saving (Please wait)",
    );
  });

  it("leaves the button alone when the form is invalid", async () => {
    await mount(page(button));
    vi.useFakeTimers();
    $("r").value = "";
    submit();
    vi.advanceTimersByTime(0);
    expect($("waiting-save-button").disabled).toBe(false);
  });

  it("copes with a form without the button", async () => {
    await mount(page());
    expect(submit).not.toThrow();
  });
});
