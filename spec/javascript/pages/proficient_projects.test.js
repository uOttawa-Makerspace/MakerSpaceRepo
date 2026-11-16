// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("datatables.net-bs5", () => ({ default: class {} }));

const $ = (id) => document.getElementById(id);

// Each example imports the page script afresh over its page, without a
// turbo:load, as Turbo does when it adds the script on a visit after that
// visit's turbo:load. The listeners of the import are removed afterwards.
const documentListeners = [];
async function importOver(html) {
  document.body.innerHTML = html;
  vi.resetModules();
  const listen = vi.spyOn(document, "addEventListener");
  await import("../../../app/javascript/entrypoints/proficient_projects.js");
  documentListeners.push(...listen.mock.calls.map(([type, fn]) => [type, fn]));
  listen.mockRestore();
}
const turboLoad = () => document.dispatchEvent(new Event("turbo:load"));

afterEach(() => {
  for (const [type, fn] of documentListeners.splice(0)) {
    document.removeEventListener(type, fn);
  }
});

const form = `
  <button class="pp-status-button">Awarded</button>
  <div id="photos">
    <div class="input-group">
      <input type="file" id="images_">
      <button id="new-photo-input" data-remove-label="Remove"><i></i></button>
    </div>
  </div>
  <table><tr><td><span id="7" class="file-remove">remove</span></td></tr></table>
  <input type="hidden" id="deletefiles" value="">
  <div><img class="image-item"><span id="9" class="image-remove"></span></div>
  <input type="hidden" id="deleteimages" value="">
  <div id="link-container">
    <div class="tr-row"><select></select><button class="tr-delete-button"><i></i></button></div>
  </div>
  <button id="new-tr">New Requirement</button>
  <div id="new-link-input" style="visibility: hidden;"><input value="x"><button class="tr-delete-button"><i></i></button></div>`;

describe("proficient project page script reached by a Turbo visit", () => {
  it("sets up the page it came with before any turbo:load", async () => {
    await importOver(form);
    expect(document.querySelector(".pp-status-button").className).toContain(
      "btn-success",
    );
    $("new-photo-input").click();
    expect($("photos").children).toHaveLength(2);
    $("new-tr").click();
    expect($("link-container").children).toHaveLength(2);
  });

  it("binds each control once over a later load of the same page", async () => {
    await importOver(form);
    turboLoad();

    $("new-photo-input").click();
    expect($("photos").children).toHaveLength(2);
    $("new-tr").click();
    expect($("link-container").children).toHaveLength(2);
    $("7").click();
    expect($("deletefiles").value).toBe("7,");
    $("9").click();
    expect($("deleteimages").value).toBe("9,");
  });

  it("removes an added row and a requirement row with their buttons", async () => {
    await importOver(form);
    turboLoad();
    $("new-photo-input").click();
    $("photos").children[1].querySelector("button").click();
    expect($("photos").children).toHaveLength(1);
    document.querySelector(".tr-row .tr-delete-button").click();
    expect(document.querySelector(".tr-row")).toBeNull();
  });

  it("removes the rows a page restored from the cache came with", async () => {
    const restored = form
      .replace(
        "</div>\n  </div>\n  <table>",
        '</div>\n    <div class="input-group"><input type="file"><button class="btn-danger"><i></i></button></div>\n  </div>\n  <table>',
      )
      .replace(
        '<div id="link-container">',
        '<div id="link-container"><div class="added"><select></select><button class="tr-delete-button"><i></i></button></div>',
      );
    await importOver(restored);
    turboLoad();
    $("photos").querySelector(".btn-danger i").click();
    expect($("photos").children).toHaveLength(1);
    document.querySelector(".added .tr-delete-button i").click();
    expect(document.querySelector(".added")).toBeNull();
    expect(document.querySelector(".tr-row")).not.toBeNull();
  });

  it("sets up the form of a later page", async () => {
    await importOver("<p>another page</p>");
    document.body.innerHTML = form;
    turboLoad();
    $("new-photo-input").click();
    expect($("photos").children).toHaveLength(2);
  });
});
