// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const PAGE = `
<input id="search_bar">
<div class="badge_list">initial</div>
<svg id="badge"><circle r="1"/></svg>
<button id="add-to-linkedin"></button>`;

async function load(page = PAGE) {
  document.body.innerHTML = page;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/badges.js");
}

const $ = (id) => document.getElementById(id);
const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(console, "log").mockImplementation(() => {});
});

describe("page without the download button", () => {
  it("does not throw", async () => {
    const withoutButtons = PAGE.replace(/<button[^>]*><\/button>/g, "");
    await expect(load(withoutButtons)).resolves.toBeUndefined();
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
      }
      return el;
    });
  };

  it("renders the badge to a PNG once its image has loaded", async () => {
    await load();
    instrument();
    $("add-to-linkedin").click();
    expect(seen.images).toHaveLength(1);
    expect(seen.images[0].src).toContain("data:image/svg+xml;base64,");
    expect(seen.clicks).toHaveLength(0);

    seen.images[0].onload();
    expect(seen.drawn[0].slice(1)).toEqual([0, 0, 250, 250]);
    expect(seen.clicks[0].el.download).toBe("download.png");
    expect(seen.clicks[0].el.href).toBe("data:image/png;base64,AAA");
  });
});
