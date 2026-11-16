// @vitest-environment happy-dom
import { describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(target, config) {
      this.target = target;
      this.config = config;
      target.tomselect = this;
      selects.push(this);
    }
  },
}));
vi.mock("../../../app/javascript/src/file_upload.js", () => ({}));

// Each load imports the page script afresh, and removes the turbo:load
// listener of the one before, so a later page load runs only the newest.
let pageLoad;
async function load(html) {
  document.body.innerHTML = html;
  selects.length = 0;
  vi.resetModules();
  vi.spyOn(console, "log").mockImplementation(() => {});
  if (pageLoad) document.removeEventListener("turbo:load", pageLoad);
  const listen = vi.spyOn(document, "addEventListener");
  await import("../../../app/javascript/entrypoints/project_proposals.js");
  pageLoad = listen.mock.calls.find(([type]) => type === "turbo:load")[1];
  listen.mockRestore();
}

const $ = (id) => document.getElementById(id);
const links = () => [...document.querySelectorAll(".main_ul li input")];
const submit = (form) => {
  const event = new Event("submit", { cancelable: true });
  form.dispatchEvent(event);
  return event;
};

describe("categories", () => {
  it("lets a proposal pick up to five categories", async () => {
    await load('<select id="project_proposal_categories"></select>');
    expect(selects[0].target).toBe($("project_proposal_categories"));
    expect(selects[0].config.maxItems).toBe(5);
  });

  it("does not decorate the select twice", async () => {
    await load('<select id="project_proposal_categories"></select>');
    expect(selects).toHaveLength(1);
  });

  it("keeps the select's picker on a later load of the same page", async () => {
    await load('<select id="project_proposal_categories"></select>');
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(1);
  });
});

describe("later page loads", () => {
  const page = `<ul class="main_ul"></ul><button id="link-list"></button>`;

  it("binds each button once over the same page", async () => {
    await load(page);
    document.dispatchEvent(new Event("turbo:load"));
    $("link-list").click();
    expect(links()).toHaveLength(1);
  });

  it("binds the buttons of a page restored from the cache", async () => {
    await load(page);
    document.body.innerHTML = page;
    document.dispatchEvent(new Event("turbo:load"));
    $("link-list").click();
    expect(links()).toHaveLength(1);
  });

  it("does not add the saved links again to a restored page that shows them", async () => {
    const saved = `<ul class="main_ul"></ul>
      <input id="ignore_past_experiences" value="notes|https://a,https://b,">`;
    await load(saved);
    // A restored page is a copy of the page as it was left.
    const shown = document.body.innerHTML;
    document.body.innerHTML = shown;
    document.dispatchEvent(new Event("turbo:load"));
    expect(links()).toHaveLength(2);
  });
});

describe("past experience links", () => {
  const page = `<ul class="main_ul"></ul><button id="link-list"></button><button id="remove-link-list"></button>`;

  it("adds an empty link field for each click on add", async () => {
    await load(page);
    $("link-list").click();
    $("link-list").click();
    expect(links()).toHaveLength(2);
    expect(links()[0].placeholder).toBe("https://...");
    expect(links()[0].classList.contains("form-control")).toBe(true);
  });

  it("removes the last link field", async () => {
    await load(page);
    $("link-list").click();
    $("link-list").click();
    links()[1].value = "second";
    $("remove-link-list").click();
    expect(links()).toHaveLength(1);
  });

  it("moves the links into the past experiences text when saving for later", async () => {
    await load(`${page}<input id="project_proposal_past_experiences" value="notes">
      <button id="waiting-save-button"></button>`);
    $("link-list").click();
    $("link-list").click();
    links()[0].value = "https://a";
    links()[1].value = "https://b";
    $("waiting-save-button").click();

    expect($("project_proposal_past_experiences").value).toBe(
      "notes|https://b,https://a,",
    );
    expect(links()).toHaveLength(0);
  });

  it("restores saved links as fields", async () => {
    await load(`<ul class="main_ul"></ul>
      <input id="ignore_past_experiences" value="notes|https://a,https://b,">`);
    expect(links().map((i) => i.value)).toEqual(["https://a", "https://b"]);
    expect(links()[0].placeholder).toBe("Ajoutez un lien / Add a link");
  });

  it("restores nothing when there are no saved links", async () => {
    await load(
      `<ul class="main_ul"></ul><input id="ignore_past_experiences" value="">`,
    );
    expect(links()).toHaveLength(0);
  });
});

describe("submit checks", () => {
  const editors = () => `
    <form id="new_project_proposal">
      <div><trix-editor input="project_proposal_client_background"></trix-editor></div>
      <div><trix-editor input="project_proposal_description"></trix-editor></div>
    </form>`;

  const fill = (background, description) => {
    const [bg, desc] = document.querySelectorAll("trix-editor");
    bg.value = background;
    desc.value = description;
    bg.focus = vi.fn();
    desc.focus = vi.fn();
    return [bg, desc];
  };

  it("lets a complete proposal through", async () => {
    await load(editors());
    fill("Acme", "A robot");
    expect(submit($("new_project_proposal")).defaultPrevented).toBe(false);
    expect(document.querySelectorAll(".invalid-feedback")).toHaveLength(0);
  });

  it("stops an empty client background and explains why", async () => {
    await load(editors());
    const [bg] = fill("", "A robot");
    const event = submit($("new_project_proposal"));
    expect(event.defaultPrevented).toBe(true);
    expect(bg.focus).toHaveBeenCalled();
    expect(bg.classList.contains("is-invalid")).toBe(true);
    expect(
      bg.parentElement.querySelector(".invalid-feedback").innerText,
    ).toContain("client's background");
  });

  it("stops an empty description and explains why", async () => {
    await load(editors());
    const [, desc] = fill("Acme", "");
    expect(submit($("new_project_proposal")).defaultPrevented).toBe(true);
    expect(desc.focus).toHaveBeenCalled();
    expect(
      desc.parentElement.querySelector(".invalid-feedback").innerText,
    ).toContain("description of your project");
  });

  it("does not repeat the explanation on a second attempt", async () => {
    await load(editors());
    fill("", "");
    submit($("new_project_proposal"));
    submit($("new_project_proposal"));
    expect(document.querySelectorAll(".invalid-feedback")).toHaveLength(2);
  });

  it("also checks the edit form", async () => {
    await load(
      editors().replace(
        'id="new_project_proposal"',
        'class="edit_project_proposal" id="edit"',
      ),
    );
    fill("", "x");
    expect(submit($("edit")).defaultPrevented).toBe(true);
  });
});

describe("attachments", () => {
  it.each(["new-file-input", "new-photo-input"])(
    "%s adds another input row with a delete button",
    async (id) => {
      await load(
        `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="${id}"><i class="fa fa-plus"></i></button></div></div>`,
      );
      const button = document.getElementById(id);
      button.click();

      const rows = document.querySelectorAll(".input-group");
      expect(rows).toHaveLength(2);
      const clone = rows[1];
      expect(clone.querySelector("input").value).toBe("");
      expect(clone.children[1].className).toBe("btn btn-danger");
      expect(clone.children[1].children[0].className).toBe("fa fa-trash");

      clone.children[1].children[0].click();
      expect(document.querySelectorAll(".input-group")).toHaveLength(1);
    },
  );

  it.each(["new-file-input", "new-photo-input"])(
    "%s stays the only element with its id, and keeps adding rows",
    async (id) => {
      await load(
        `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="${id}" class="btn btn-success"><i class="fa fa-plus"></i></button></div></div>`,
      );
      const button = document.getElementById(id);
      button.click();
      button.click();

      expect(document.querySelectorAll(".input-group")).toHaveLength(3);
      expect([...document.querySelectorAll(`[id="${id}"]`)]).toEqual([button]);
      expect(document.querySelectorAll(".wrap [id]")).toHaveLength(1);
    },
  );

  it.each(["new-file-input", "new-photo-input"])(
    "%s rows a page restored from the cache comes back with can be removed",
    async (id) => {
      await load(
        `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="${id}" class="btn btn-success"><i class="fa fa-plus"></i></button></div><div class="input-group"><input type="file"><button type="button" class="btn btn-danger"><i class="fa fa-trash"></i></button></div></div>`,
      );
      document.querySelector(".btn-danger i").click();
      expect(document.querySelectorAll(".input-group")).toHaveLength(1);
    },
  );

  it("labels an added row's button with the add button's remove label", async () => {
    await load(
      `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="new-file-input" class="btn btn-success" aria-label="Add another file" data-remove-label="Retirer"><i class="fa fa-plus"></i></button></div></div>`,
    );
    $("new-file-input").click();
    const remove = document.querySelector(".btn-danger");
    expect(remove.getAttribute("aria-label")).toBe("Retirer");
    expect($("new-file-input").getAttribute("aria-label")).toBe(
      "Add another file",
    );
  });

  it("adds one row per click, also after a later load of the same page", async () => {
    await load(
      `<div class="wrap"><div class="input-group"><input type="file"><button type="button" id="new-file-input" class="btn btn-success"><i class="fa fa-plus"></i></button></div></div>`,
    );
    $("new-file-input").click();
    document.dispatchEvent(new Event("turbo:load"));
    $("new-file-input").click();
    expect(document.querySelectorAll(".input-group")).toHaveLength(3);
  });
});
