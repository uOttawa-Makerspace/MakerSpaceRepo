// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import { Application } from "@hotwired/stimulus";

import IcsLinks from "../../../app/javascript/controllers/ics_links_controller.js";

const PAGE = `
<div data-controller="ics-links">
  <form><div id="link-container" data-ics-links-target="list">
    <div class="row"><input value="https://a.example/x.ics"><button class="del" type="button" data-action="click->ics-links#remove"></button></div>
  </div>
  <button type="button" id="new-calendar" data-action="click->ics-links#add"></button></form>
  <div id="new-link-input" style="visibility: hidden;" data-ics-links-target="template">
    <input value="prefilled"><button class="del" type="button" data-action="click->ics-links#remove"></button>
  </div>
</div>`;

let application;
async function boot() {
  document.body.innerHTML = PAGE;
  application = Application.start();
  application.register("ics-links", IcsLinks);
  await new Promise((resolve) => setTimeout(resolve, 0));
}

afterEach(() => {
  application.stop();
  document.body.innerHTML = "";
});

describe("imported calendar links", () => {
  it("adds a blank visible row that is not a second template", async () => {
    await boot();
    document.getElementById("new-calendar").click();
    const rows = document.querySelectorAll("#link-container > div");
    expect(rows).toHaveLength(2);
    const added = rows[1];
    expect(added.querySelector("input").value).toBe("");
    expect(added.style.visibility).toBe("visible");
    expect(added.id).toBe("");
    expect(added.hasAttribute("data-ics-links-target")).toBe(false);
    expect(document.getElementById("new-link-input")).not.toBeNull();
  });

  it("removes a row on its delete button, for existing and added rows", async () => {
    await boot();
    document.getElementById("new-calendar").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    const buttons = document.querySelectorAll("#link-container .del");
    expect(buttons).toHaveLength(2);
    buttons[1].click();
    buttons[0].click();
    expect(document.querySelectorAll("#link-container > div")).toHaveLength(0);
  });
});
