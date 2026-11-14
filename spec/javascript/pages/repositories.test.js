// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(target, config) {
      this.target = target;
      this.el =
        typeof target === "string" ? document.querySelector(target) : target;
      this.config = config;
      this.el.tomselect = this;
      selects.push(this);
    }
  },
}));
vi.mock("../../../app/javascript/src/file_upload.js", () => ({}));
const toasts = vi.hoisted(() => []);
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

await import("../../../app/javascript/entrypoints/repositories.js");

const $ = (id) => document.getElementById(id);
const load = (html) => {
  document.body.innerHTML = html;
  selects.length = 0;
  document.dispatchEvent(new Event("turbo:load"));
};
const byId = (id) => selects.find((s) => s.el.id === id);

const IDS = [
  "owner_select",
  "search_users_add",
  "search_users_remove",
  "search_users_transfer",
  "search_project_proposals",
  "repository_categories",
  "repository_equipments",
  "repository_project_proposal_id",
];
const allSelects = IDS.map((id) => `<select id="${id}"></select>`).join("");

afterEach(() => {
  document.body.innerHTML = "";
});

describe("repository selects", () => {
  it("decorates every select on the page, in page script order, by its id selector", () => {
    load(
      [...IDS]
        .reverse()
        .map((id) => `<select id="${id}"></select>`)
        .join(""),
    );
    expect(selects.map((s) => s.target)).toEqual(IDS.map((id) => `#${id}`));
  });

  it("gives each select its own options", () => {
    load(allSelects);
    expect(byId("owner_select").config).toEqual({
      searchField: ["username"],
      valueField: "id",
      labelField: "username",
      maxOptions: 5,
      searchPlaceholder: "Add Owner...",
      searchOnKeyUp: true,
      openOnFocus: false,
      load: expect.any(Function),
      shouldLoad: expect.any(Function),
    });
    expect(byId("search_users_add").config).toEqual({
      searchField: ["username"],
      valueField: "id",
      labelField: "username",
      maxOptions: 5,
      searchPlaceholder: "Add Owner...",
      searchOnKeyUp: true,
      load: expect.any(Function),
      shouldLoad: expect.any(Function),
    });
    const listed = {
      searchField: ["username"],
      valueField: "id",
      labelField: "username",
      maxOptions: null,
      searchOnKeyUp: true,
    };
    expect(byId("search_users_remove").config).toEqual(listed);
    expect(byId("search_users_transfer").config).toEqual(listed);
    expect(byId("search_project_proposals").config).toEqual({
      render: { option: expect.any(Function), item: expect.any(Function) },
    });
    expect(byId("repository_categories").config).toEqual({
      plugins: ["remove_button"],
      maxItems: 5,
      openOnFocus: true,
    });
    expect(byId("repository_equipments").config).toEqual({
      plugins: ["remove_button"],
      maxItems: 5,
      openOnFocus: true,
      create: true,
    });
    expect(byId("repository_project_proposal_id").config).toEqual({
      plugins: ["clear_button"],
      maxItems: 1,
    });
  });

  it("does not decorate a select twice when the page loads again", () => {
    load(allSelects);
    selects.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(0);
  });

  it("leaves alone each select that is already decorated", () => {
    document.body.innerHTML = allSelects;
    IDS.forEach((id) => ($(id).tomselect = "existing"));
    selects.length = 0;
    document.dispatchEvent(new Event("turbo:load"));
    expect(selects).toHaveLength(0);
    expect(IDS.map((id) => $(id).tomselect)).toEqual(IDS.map(() => "existing"));
  });

  it("does nothing on a page without any of the selects", () => {
    load("<p>nothing here</p>");
    expect(selects).toHaveLength(0);
  });

  it("decorates only the selects that are present", () => {
    load('<select id="repository_equipments"></select>');
    expect(selects.map((s) => s.target)).toEqual(["#repository_equipments"]);
  });
});

describe.each(["owner_select", "search_users_add"])(
  "user search on %s",
  (id) => {
    const config = () => {
      load(`<select id="${id}"></select>`);
      return byId(id).config;
    };

    it("only asks the server once more than two characters are typed", () => {
      const { shouldLoad } = config();
      expect(shouldLoad("")).toBe(false);
      expect(shouldLoad("ab")).toBe(false);
      expect(shouldLoad("abc")).toBe(true);
    });

    const answer = (body, init = {}) =>
      vi.fn(async () => new Response(JSON.stringify(body), init));

    it("offers the id and username of each user the server finds", async () => {
      const fetchMock = answer({
        users: [
          { id: 4, username: "ann", name: "Ann" },
          { id: 7, username: "bob", email: "b@example.com" },
        ],
      });
      vi.stubGlobal("fetch", fetchMock);
      const callback = vi.fn();
      config().load("ann", callback);
      await vi.waitFor(() => expect(callback).toHaveBeenCalled());
      expect(fetchMock.mock.calls[0][0]).toBe(
        "/repositories/populate_users?search=ann",
      );
      expect(callback).toHaveBeenCalledWith([
        { id: 4, username: "ann" },
        { id: 7, username: "bob" },
      ]);
    });

    it("sends the typed text encoded, so spaces, & # and + reach the server", async () => {
      const fetchMock = answer({ users: [] });
      vi.stubGlobal("fetch", fetchMock);
      const callback = vi.fn();
      config().load("a b&c#d+e", callback);
      await vi.waitFor(() => expect(callback).toHaveBeenCalledWith([]));
      const url = new URL(fetchMock.mock.calls[0][0], "http://example.test");
      expect(url.pathname).toBe("/repositories/populate_users");
      expect([...url.searchParams]).toEqual([["search", "a b&c#d+e"]]);
    });

    it("shows the server's error and answers with no options when the search fails", async () => {
      toasts.length = 0;
      vi.stubGlobal(
        "fetch",
        answer({ error: "Search unavailable" }, { status: 500 }),
      );
      const callback = vi.fn();
      config().load("ann", callback);
      await vi.waitFor(() => expect(callback).toHaveBeenCalled());
      expect(callback).toHaveBeenCalledWith();
      expect(toasts).toEqual([
        { message: "Search unavailable", type: "error" },
      ]);
    });

    it("tells the user and answers with no options when the server is unreachable", async () => {
      toasts.length = 0;
      document.documentElement.dataset.requestNetwork = "Server unreachable";
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => {
          throw new TypeError("Failed to fetch");
        }),
      );
      const callback = vi.fn();
      config().load("ann", callback);
      await vi.waitFor(() => expect(callback).toHaveBeenCalled());
      expect(callback).toHaveBeenCalledWith();
      expect(toasts).toEqual([
        { message: "Server unreachable", type: "error" },
      ]);
      delete document.documentElement.dataset.requestNetwork;
    });

    it("treats an answer that is not JSON as a failed search", async () => {
      toasts.length = 0;
      document.documentElement.dataset.requestFailed = "Request failed";
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => new Response("<html>sign in</html>")),
      );
      const callback = vi.fn();
      config().load("ann", callback);
      await vi.waitFor(() => expect(callback).toHaveBeenCalled());
      expect(callback).toHaveBeenCalledWith();
      expect(toasts).toEqual([{ message: "Request failed", type: "error" }]);
      delete document.documentElement.dataset.requestFailed;
    });
  },
);

describe("project proposal select", () => {
  const render = () => {
    load('<select id="search_project_proposals"></select>');
    return byId("search_project_proposals").config.render;
  };
  const escape = (s) => `[${s}]`;

  it("shows the proposal title with its semester in the list", () => {
    expect(render().option({ text: "Robot", semester: "Fall" }, escape))
      .toBe(`<div>
            <span>[Robot]</span>
            <br />
            <small class="text-muted">[Fall]</small>
            </div>`);
  });

  it("shows the chosen proposal title with its semester", () => {
    expect(render().item({ text: "Robot", semester: "Fall" }, escape))
      .toBe(`<span>
            [Robot]
            <br />
            <small class="text-muted">[Fall]</small>
            </span>`);
  });

  it("leaves the semester blank when a proposal has none", () => {
    const { option, item } = render();
    expect(option({ text: "Robot" }, escape)).toContain(
      '<small class="text-muted">[]</small>',
    );
    expect(item({ text: "Robot", semester: null }, escape)).toContain(
      '<small class="text-muted">[]</small>',
    );
  });
});

describe("repository password field", () => {
  it("shows the password section", () => {
    document.body.innerHTML = '<div id="pass" style="display:none"></div>';
    window.showPass();
    expect($("pass").style.display).toBe("block");
  });

  it("hides the password change and password sections when present", () => {
    document.body.innerHTML =
      '<div id="change_pass"></div><div id="pass"></div>';
    window.hidePass();
    expect($("change_pass").style.display).toBe("none");
    expect($("pass").style.display).toBe("none");
    document.body.innerHTML = "";
    expect(() => window.hidePass()).not.toThrow();
  });

  it("toggles the password field", () => {
    document.body.innerHTML =
      '<input id="password_repo_field" style="display:none">';
    window.togglePass();
    expect($("password_repo_field").style.display).toBe("block");
    window.togglePass();
    expect($("password_repo_field").style.display).toBe("none");
  });
});
