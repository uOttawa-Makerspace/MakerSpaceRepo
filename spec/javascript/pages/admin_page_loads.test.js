// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(el, config) {
      this.el = el;
      this.config = config;
      el.tomselect = this;
      selects.push(this);
    }
  },
}));
const sortables = [];
vi.mock("sortablejs", () => ({
  default: class {
    constructor(el, options) {
      this.el = el;
      this.options = options;
      this.option = vi.fn();
      sortables.push(this);
    }
  },
}));
vi.mock("datatables.net-bs5", () => ({ default: class {} }));

const $ = (id) => document.getElementById(id);

// Each example imports a page script afresh over its page, without a
// turbo:load, as Turbo does when it adds the script on a visit after that
// visit's turbo:load. The listeners of the import are removed afterwards.
const documentListeners = [];
async function importOver(html, entrypoint) {
  document.body.innerHTML = html;
  selects.length = 0;
  sortables.length = 0;
  vi.resetModules();
  const listen = vi.spyOn(document, "addEventListener");
  await import(`../../../app/javascript/entrypoints/${entrypoint}.js`);
  documentListeners.push(...listen.mock.calls.map(([type, fn]) => [type, fn]));
  listen.mockRestore();
}
const turboLoad = () => document.dispatchEvent(new Event("turbo:load"));

afterEach(() => {
  for (const [type, fn] of documentListeners.splice(0)) {
    document.removeEventListener(type, fn);
  }
});

describe.each([
  ["trainings", '<select id="training_list_of_skills_en"></select>'],
  ["job_options", '<select id="job_type_ids_option"></select>'],
  ["contact_infos", '<select id="contact_info_space_id"></select>'],
  ["admin_spaces", '<select id="space-manager-select"></select>'],
  ["teams", '<select id="search_users_add"></select>'],
  ["questions", '<select id="questions_trainings"></select>'],
  ["staff_training_sessions", '<select id="user_id"></select>'],
  ["learning_modules", '<select id="learning_module_subskill"></select>'],
])("%s page script", (entrypoint, html) => {
  it("builds the picker of the page it came with before any turbo:load", async () => {
    await importOver(html, entrypoint);
    expect(selects.map((s) => s.el)).toEqual([
      document.querySelector("select"),
    ]);
  });

  it("keeps that one picker on a later load of the same page", async () => {
    await importOver(html, entrypoint);
    turboLoad();
    expect(selects).toHaveLength(1);
  });

  it("builds the picker of a later page", async () => {
    await importOver("<p>another page</p>", entrypoint);
    document.body.innerHTML = html;
    turboLoad();
    expect(selects).toHaveLength(1);
  });
});

describe("contact info form over two loads of the same page", () => {
  const page = `
    <input type="checkbox" id="closed">
    <fieldset id="hours" data-toggled-by="#closed"></fieldset>
    <div id="openingHours"></div>
    <div id="newOpeningHourSubForm" hidden><input name="CHILDINDEX"></div>
    <button id="addNewOpeningHour"></button>`;

  it("adds one opening hour form per click", async () => {
    await importOver(page, "contact_infos");
    turboLoad();
    $("addNewOpeningHour").click();
    expect($("openingHours").children).toHaveLength(1);
  });

  it("listens to the checkbox once and disables its fieldset", async () => {
    await importOver(page, "contact_infos");
    turboLoad();
    const changes = vi.fn();
    $("closed").addEventListener("change", changes);
    turboLoad();
    expect(changes).not.toHaveBeenCalled();
    $("closed").checked = true;
    $("closed").dispatchEvent(new Event("change"));
    expect($("hours").disabled).toBe(true);
  });
});

describe("question form over two loads of the same page", () => {
  it("listens to the picture input once", async () => {
    await importOver('<input type="file" id="pictureInput">', "questions");
    const listen = vi.spyOn($("pictureInput"), "addEventListener");
    turboLoad();
    expect(listen).not.toHaveBeenCalled();
  });
});

describe("learning module list over two loads of the same page", () => {
  it("makes the list sortable once", async () => {
    await importOver(
      '<input type="checkbox" data-order="a"><div data-order-container="a"></div>',
      "learning_modules",
    );
    turboLoad();
    expect(sortables).toHaveLength(1);
  });
});
