// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import { Application } from "@hotwired/stimulus";

import SupervisorField from "../../../app/javascript/controllers/supervisor_field_controller.js";

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
});

async function mount() {
  const radio = (value) =>
    `<input type="radio" name="identity" id="identity_${value}" value="${value}" data-action="click->supervisor-field#toggle">`;
  document.body.innerHTML = `
    <form data-controller="supervisor-field">
      ${["JMTS", "Staff", "GNG", "Other"].map(radio).join("")}
      <div id="supervisor-select" style="display: none;" data-supervisor-field-target="supervisor"></div>
    </form>`;
  application = Application.start();
  application.register("supervisor-field", SupervisorField);
  await settle();
}

const display = () =>
  document.getElementById("supervisor-select").style.display;

describe("supervisor-field", () => {
  it("shows the supervisor list only while Staff is chosen", async () => {
    await mount();
    expect(display()).toBe("none");
    document.getElementById("identity_Staff").click();
    expect(display()).toBe("block");
    document.getElementById("identity_GNG").click();
    expect(display()).toBe("none");
    document.getElementById("identity_Staff").click();
    document.getElementById("identity_Other").click();
    expect(display()).toBe("none");
  });
});
