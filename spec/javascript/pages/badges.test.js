// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const selects = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(target, config) {
      const el =
        typeof target === "string" ? document.querySelector(target) : target;
      this.el = el;
      this.config = config;
      el.tomselect = this;
      selects.push(this);
    }
  },
}));
const tables = [];
vi.mock("datatables.net-bs5", () => ({
  default: class {
    constructor(selector) {
      tables.push(selector);
    }
  },
}));
vi.mock("datatables.net-bs5/css/dataTables.bootstrap5.min.css", () => ({}));

const PAGE = `
<select class="link-pp" id="pp1"></select><select class="link-pp" id="pp2"></select>
<select id="grant_user_select"></select>
<select id="revoke_user_select"></select>
<input id="search_bar">
<div class="badge_list">initial</div>
<svg id="badge"><circle r="1"/></svg>
<button id="add-to-linkedin"></button>
<button id="downloadSVG"></button>
<button id="downloadPNG"></button>
<table id="badge-table"></table>
<table id="awarded-badge-table"></table>`;

async function load(page = PAGE) {
  document.body.innerHTML = page;
  selects.length = 0;
  tables.length = 0;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/badges.js");
}

const $ = (id) => document.getElementById(id);
const byEl = (id) => selects.find((s) => s.el.id === id);
const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(console, "log").mockImplementation(() => {});
});

describe("selects and tables", () => {
  it("decorates each link select, the user pickers and the two tables", async () => {
    await load();
    expect(byEl("pp1")).toBeDefined();
    expect(byEl("pp2")).toBeDefined();
    expect(byEl("grant_user_select")).toBeDefined();
    expect(byEl("revoke_user_select")).toBeDefined();
    expect(tables).toEqual(["#badge-table", "#awarded-badge-table"]);
  });

  it("creates no table and does not throw on a page without the tables", async () => {
    const withoutTables = PAGE.replace(/<table[^>]*><\/table>/g, "");
    await expect(load(withoutTables)).resolves.toBeUndefined();
    expect(tables).toEqual([]);
  });

  it("does not throw on a page without the download and LinkedIn buttons", async () => {
    const withoutButtons = PAGE.replace(/<button[^>]*><\/button>/g, "");
    await expect(load(withoutButtons)).resolves.toBeUndefined();
    expect(tables).toEqual(["#badge-table", "#awarded-badge-table"]);
  });

  it("only loads names once at least three characters are typed", async () => {
    await load();
    for (const id of ["grant_user_select", "revoke_user_select"]) {
      const { shouldLoad } = byEl(id).config;
      expect(shouldLoad("ab")).toBe(false);
      expect(shouldLoad("abc")).toBe(true);
    }
  });

  it.each([
    ["grant_user_select", "/badges/populate_grant_users?search=ann"],
    ["revoke_user_select", "/badges/populate_revoke_users?search=ann"],
  ])("%s asks the server and hands over id and name", async (id, url) => {
    await load();
    const fetchMock = vi.fn(async () => ({
      json: async () => ({ users: [{ id: 3, name: "Ann", extra: "x" }] }),
    }));
    vi.stubGlobal("fetch", fetchMock);
    const callback = vi.fn();

    byEl(id).config.load("ann", callback);
    await flush();

    expect(fetchMock).toHaveBeenCalledWith(url);
    expect(callback).toHaveBeenCalledWith([{ id: 3, name: "Ann" }]);
  });

  it("does not ask the server for a very short search", async () => {
    await load();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    byEl("grant_user_select").config.load("a", vi.fn());
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("badge search", () => {
  const search = async (value) => {
    $("search_bar").value = value;
    const event = new Event("keyup", { cancelable: true });
    $("search_bar").dispatchEvent(event);
    await flush();
    return event;
  };
  const stub = () => {
    const fetchMock = vi.fn(async () => ({ text: async () => "<p>list</p>" }));
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  };

  it("filters the badge list for a search of three characters or more", async () => {
    await load();
    const fetchMock = stub();
    const event = await search("laser");
    expect(event.defaultPrevented).toBe(true);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/badges?search=laser");
    expect(init.headers["X-Requested-With"]).toBe("XMLHttpRequest");
    expect(document.querySelector(".badge_list").innerHTML).toBe("<p>list</p>");
  });

  it("searches for a single dot", async () => {
    await load();
    const fetchMock = stub();
    await search(".");
    expect(fetchMock.mock.calls[0][0]).toBe("/badges?search=.");
  });

  it("reloads the whole list when the box is emptied", async () => {
    await load();
    const fetchMock = stub();
    await search("");
    expect(fetchMock.mock.calls).toHaveLength(1);
    expect(fetchMock.mock.calls[0][0]).toBe("/badges");
  });

  it("waits for more characters on a short search", async () => {
    await load();
    const fetchMock = stub();
    await search("la");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("downloads", () => {
  // Wraps element creation so anchors record their click, canvases record what
  // is drawn, and images are handed back for the test to trigger onload.
  let seen;
  const instrument = () => {
    seen = { clicks: [], images: [], drawn: [] };
    const create = Document.prototype.createElement;
    vi.spyOn(document, "createElement").mockImplementation(function (tag) {
      const el = create.call(this, tag);
      if (tag === "a") {
        el.dispatchEvent = (event) => seen.clicks.push({ el, event });
      }
      if (tag === "img") seen.images.push(el);
      if (tag === "canvas") {
        el.getContext = () => ({
          drawImage: (...args) => seen.drawn.push(args),
        });
        el.toDataURL = () => "data:image/png;base64,AAA";
        el.msToBlob = () => "blob";
      }
      return el;
    });
  };

  it("offers the badge as an SVG file", async () => {
    await load();
    instrument();
    $("downloadSVG").click();
    expect(seen.clicks).toHaveLength(1);
    expect(seen.clicks[0].el.download).toBe("download.svg");
    expect(seen.clicks[0].el.href).toContain("data:image/svg+xml;base64,");
  });

  it("renders the badge to a PNG once its image has loaded", async () => {
    await load();
    instrument();
    $("downloadPNG").click();
    expect(seen.images).toHaveLength(1);
    expect(seen.images[0].src).toContain("data:image/svg+xml;base64,");
    expect(seen.clicks).toHaveLength(0);

    seen.images[0].onload();
    expect(seen.drawn[0].slice(1)).toEqual([0, 0, 250, 250]);
    expect(seen.clicks[0].el.download).toBe("download.png");
    expect(seen.clicks[0].el.href).toBe("data:image/png;base64,AAA");
  });

  it("the LinkedIn button also produces the PNG", async () => {
    await load();
    instrument();
    $("add-to-linkedin").click();
    seen.images[0].onload();
    expect(seen.clicks[0].el.download).toBe("download.png");
  });

  it("saves through the old IE call when the browser has it", async () => {
    await load();
    instrument();
    const msSaveBlob = vi.fn();
    window.navigator.msSaveBlob = msSaveBlob;
    const event = new Event("click", { cancelable: true });
    $("add-to-linkedin").dispatchEvent(event);
    seen.images[0].onload();
    expect(msSaveBlob).toHaveBeenCalledWith("blob", "download.png");
    expect(event.defaultPrevented).toBe(true);
    expect(seen.clicks).toHaveLength(0);
    delete window.navigator.msSaveBlob;
  });
});
