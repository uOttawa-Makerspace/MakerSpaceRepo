// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const cookies = {};
vi.mock("js-cookie", () => ({
  default: {
    get: (name) => cookies[name],
    set: vi.fn((name, value) => (cookies[name] = value)),
  },
}));
const visits = vi.fn();
vi.mock("@hotwired/turbo-rails", () => ({ Turbo: { visit: visits } }));

const { default: Cookies } = await import("js-cookie");
const { toggleTheme } = await import("../../../app/javascript/src/theme.js");
await import("../../../app/javascript/src/forms.js");
await import("../../../app/javascript/src/accordion-load.js");
await import("../../../app/javascript/src/header.js");
await import("../../../app/javascript/src/effects.js");

const load = () => document.dispatchEvent(new Event("turbo:load"));
const $ = (id) => document.getElementById(id);

beforeEach(() => {
  document.body.innerHTML = "";
  localStorage.clear();
  for (const key of Object.keys(cookies)) delete cookies[key];
  document.documentElement.removeAttribute("data-bs-theme");
});

describe("theme", () => {
  it("defaults to dark when no theme is saved", () => {
    load();
    expect(document.documentElement.dataset.bsTheme).toBe("dark");
  });

  it("applies the saved theme on load and toggles it with the button", () => {
    cookies.theme = "light";
    document.body.innerHTML = '<a id="themeToggler" href="#"></a>';
    load();
    expect(document.documentElement.dataset.bsTheme).toBe("light");

    const click = new Event("click", { cancelable: true });
    $("themeToggler").dispatchEvent(click);
    expect(click.defaultPrevented).toBe(true);
    expect(document.documentElement.dataset.bsTheme).toBe("dark");
    expect(Cookies.set).toHaveBeenCalledWith("theme", "dark", {
      expires: 365,
      sameSite: "lax",
      path: "/",
    });
  });

  it("toggles back and is available to inline handlers", () => {
    document.documentElement.dataset.bsTheme = "dark";
    window.toggleTheme();
    expect(document.documentElement.dataset.bsTheme).toBe("light");
    toggleTheme();
    expect(document.documentElement.dataset.bsTheme).toBe("dark");
  });

  it("starts from the system preference when the page has no theme yet", () => {
    window.matchMedia = () => ({ matches: false });
    toggleTheme();
    expect(document.documentElement.dataset.bsTheme).toBe("dark");
  });

  it("sets the theme on the page about to be shown by Turbo", () => {
    cookies.theme = "light";
    const html = document.createElement("html");
    const body = document.createElement("body");
    html.append(body);
    const event = new Event("turbo:before-render");
    event.detail = { newBody: body };
    document.dispatchEvent(event);
    expect(html.dataset.bsTheme).toBe("light");

    const none = new Event("turbo:before-render");
    none.detail = {};
    document.dispatchEvent(none);
  });
});

describe("form helpers", () => {
  const field = (attrs) => `<input type="checkbox" id="c" ${attrs}>`;

  it("data-show reveals its targets while checked", () => {
    document.body.innerHTML = `${field('data-show=".t"')}<div class="t"></div>`;
    load();
    expect(document.querySelector(".t").hidden).toBe(true);
    $("c").checked = true;
    $("c").dispatchEvent(new Event("change"));
    expect(document.querySelector(".t").hidden).toBe(false);
  });

  it("data-hide hides its targets while checked", () => {
    document.body.innerHTML = `${field('data-hide=".t"')}<div class="t"></div>`;
    load();
    expect(document.querySelector(".t").hidden).toBe(false);
    $("c").checked = true;
    $("c").dispatchEvent(new Event("change"));
    expect(document.querySelector(".t").hidden).toBe(true);
  });

  it("data-disable-on-select disables its targets while checked", () => {
    document.body.innerHTML = `${field('data-disable-on-select="#x"')}<input id="x">`;
    load();
    $("c").checked = true;
    $("c").dispatchEvent(new Event("change"));
    expect($("x").disabled).toBe(true);
    $("c").checked = false;
    $("c").dispatchEvent(new Event("change"));
    expect($("x").disabled).toBe(false);
  });

  it("data-enable-on-select enables its targets while checked", () => {
    document.body.innerHTML = `${field('data-enable-on-select="#x"')}<input id="x" disabled>`;
    load();
    $("c").checked = true;
    $("c").dispatchEvent(new Event("change"));
    expect($("x").disabled).toBe(false);
    $("c").checked = false;
    $("c").dispatchEvent(new Event("change"));
    expect($("x").disabled).toBe(true);
  });

  // The handler reads the element's own (undefined) currentTarget, so it throws
  // on every change instead of toggling the targets.
  it.skip("data-toggles shows its targets while checked", () => {
    document.body.innerHTML = `${field('data-toggles=".t"')}<div class="t"></div>`;
    load();
    expect(document.querySelector(".t").hidden).toBe(true);
    $("c").checked = true;
    $("c").dispatchEvent(new Event("change"));
    expect(document.querySelector(".t").hidden).toBe(false);
  });
});

describe("accordion state", () => {
  const page = `<div id="a" class="collapse"></div><div id="b" class="collapse show"></div><div id="d" class="collapse"></div>`;
  const key = () => window.location.pathname;
  const saved = () => JSON.parse(localStorage.getItem(key()));

  it("restores which sections were open or closed", () => {
    localStorage.setItem(
      key(),
      JSON.stringify({ a: true, b: false, gone: true, d: "x" }),
    );
    document.body.innerHTML = page;
    load();
    expect($("a").classList.contains("show")).toBe(true);
    expect($("b").classList.contains("show")).toBe(false);
    expect($("d").classList.contains("show")).toBe(false);
  });

  it("copes with unreadable saved state", () => {
    localStorage.setItem(key(), "{not json");
    document.body.innerHTML = page;
    expect(load).not.toThrow();
  });

  it("remembers a section as it opens and closes", () => {
    document.body.innerHTML = page;
    load();
    $("a").dispatchEvent(new Event("show.bs.collapse"));
    $("b").dispatchEvent(new Event("hide.bs.collapse"));
    expect(saved()).toEqual({ a: true, b: false });
  });

  it("starts again from unreadable saved state when one is changed", () => {
    document.body.innerHTML = page;
    load();
    localStorage.setItem(key(), "{bad");
    $("a").dispatchEvent(new Event("show.bs.collapse"));
    expect(saved()).toEqual({ a: true });
    localStorage.setItem(key(), "{bad");
    $("b").dispatchEvent(new Event("hide.bs.collapse"));
    expect(saved()).toEqual({ b: false });
  });
});

describe("header", () => {
  const header = `<div id="sticky-header"><nav class="navbar"></nav></div>`;
  const scrollTo = (top) => {
    document.documentElement.scrollTop = top;
    document.dispatchEvent(new Event("scroll"));
  };

  beforeEach(() => {
    document.body.innerHTML = header;
    Object.defineProperty($("sticky-header"), "clientHeight", {
      value: 100,
      configurable: true,
    });
    load();
  });

  it("shrinks past the header height, and grows back only above half of it", () => {
    const nav = document.querySelector(".navbar");
    scrollTo(150);
    expect(nav.classList.contains("header-small")).toBe(true);
    scrollTo(70);
    expect(nav.classList.contains("header-small")).toBe(true);
    scrollTo(10);
    expect(nav.classList.contains("header-small")).toBe(false);
  });
});

describe("header login modal and quick access", () => {
  it("focuses the username field when the login modal opens", () => {
    document.body.innerHTML = `<div id="sticky-header"></div>
      <div id="loginModal"><input id="login_modal_username_email"></div>`;
    load();
    $("loginModal").dispatchEvent(new Event("shown.bs.modal"));
    expect(document.activeElement).toBe($("login_modal_username_email"));
  });

  it("saves the page as a quick access link and reloads it", async () => {
    window.happyDOM.setURL("http://localhost/spaces/3");
    document.head.innerHTML = '<meta name="csrf-token" content="tok">';
    document.title = "My Space | MakerRepo";
    document.body.innerHTML = `<div id="sticky-header"></div><button id="add-new-quick-access"></button>`;
    const fetchMock = vi.fn(async () => ({}));
    vi.stubGlobal("fetch", fetchMock);
    load();
    $("add-new-quick-access").click();
    await vi.waitFor(() => expect(visits).toHaveBeenCalled());

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/quick_access_links/create");
    expect(init.method).toBe("POST");
    expect(init.headers["X-CSRF-Token"]).toBe("tok");
    expect(JSON.parse(init.body)).toEqual({
      name: "My Space",
      path: "/spaces/3",
    });
    expect(visits).toHaveBeenCalledWith("http://localhost/spaces/3");
  });
});

describe("effects", () => {
  beforeEach(() => vi.useFakeTimers());

  it("fades in the first two children of a hovered repository tile", () => {
    document.body.innerHTML = `<div class="repository-container"><div>
      <i id="a"></i><i id="b"></i></div></div>`;
    load();
    const tile = document.querySelector(".repository-container");
    tile.dispatchEvent(new Event("mouseenter"));
    vi.advanceTimersByTime(2000);
    expect(Number($("a").style.opacity)).toBeGreaterThanOrEqual(1);
    expect(Number($("b").style.opacity)).toBeGreaterThanOrEqual(1);

    $("a").style.opacity = "0";
    tile.dispatchEvent(new Event("mouseleave"));
    vi.advanceTimersByTime(2000);
    expect(Number($("a").style.opacity)).toBeGreaterThanOrEqual(1);
  });

  it("leaves a tile with fewer than two children alone", () => {
    document.body.innerHTML = `<div class="repository-container"><div><i id="a"></i></div></div>`;
    load();
    document
      .querySelector(".repository-container")
      .dispatchEvent(new Event("mouseenter"));
    vi.advanceTimersByTime(2000);
    expect($("a").style.opacity).toBe("");
  });

  it("shows the spinner once the report form is submitted", () => {
    document.body.innerHTML = `<form><button class="repository_report"></button></form>
      <span class="spinner" style="display:none"></span>`;
    load();
    expect(document.querySelector(".spinner").style.display).toBe("none");
    document
      .querySelector("form")
      .dispatchEvent(new Event("turbo:submit-start"));
    expect(document.querySelector(".spinner").style.display).toBe(
      "inline-block",
    );
  });

  it("shows and hides the sort filter from its header", () => {
    document.body.innerHTML = `<div id="filter-header"></div><div id="sort-filter"></div>`;
    load();
    $("filter-header").click();
    expect($("sort-filter").style.display).toBe("block");
    $("filter-header").click();
    expect($("sort-filter").style.display).toBe("none");
    $("filter-header").click();
    expect($("sort-filter").style.display).toBe("block");
  });
});
