// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

const modal = { show: vi.fn(), hide: vi.fn() };
let existingInstance = null;
vi.mock("bootstrap", () => ({
  Modal: {
    getOrCreateInstance: () => modal,
    getInstance: () => existingInstance,
  },
}));

const { default: LaunchModal } =
  await import("../../../app/javascript/controllers/launch-modal_controller.js");
const { default: LaunchCustomModal } =
  await import("../../../app/javascript/controllers/launch-custom-modal_controller.js");
const { default: CommentsModal } =
  await import("../../../app/javascript/controllers/job-order-comments-modal_controller.js");
const { default: VolunteerSearch } =
  await import("../../../app/javascript/controllers/volunteer_search_controller.js");

const { default: Confirmation } =
  await import("../../../app/javascript/controllers/confirmation_controller.js");

let application;
const $ = (id) => document.getElementById(id);
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(html) {
  document.body.innerHTML = html;
  application = Application.start();
  application.register("launch-modal", LaunchModal);
  application.register("launch-custom-modal", LaunchCustomModal);
  application.register("job-order-comments-modal", CommentsModal);
  application.register("volunteer-search", VolunteerSearch);
  application.register("confirmation", Confirmation);
  await settle();
}

beforeEach(() => {
  modal.show.mockClear();
  modal.hide.mockClear();
  existingInstance = null;
});

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  document.body.className = "";
});

describe("launch-modal", () => {
  const page = `
    <section data-controller="launch-modal" id="root">
      <button id="open" data-action="click->launch-modal#openModal"
              data-id="7" data-title="Laser job" data-url="/jobs/7" data-name="order"></button>
      <button id="close" data-action="click->launch-modal#close"></button>
      <div id="order-modal">
        <span data-launch-modal-target="id"></span><span data-launch-modal-target="id"></span>
        <b data-launch-modal-target="title"></b>
        <div id="order-body">old</div>
      </div>
    </section>`;

  it("fills the dialog from the button, loads the page into it and shows it", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ text: async () => "<p id='loaded'>details</p>" })),
    );
    await mount(page);
    $("open").click();
    await vi.waitFor(() => expect(modal.show).toHaveBeenCalled());

    expect(fetch).toHaveBeenCalledWith("/jobs/7");
    expect(
      [...document.querySelectorAll('[data-launch-modal-target="id"]')].map(
        (e) => e.innerText,
      ),
    ).toEqual(["7", "7"]);
    expect(document.querySelector("b").innerText).toBe("Laser job");
    expect($("order-body").textContent).toBe("details");
    expect($("loaded")).not.toBeNull();
  });

  it("works for a dialog with no id or title slots", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ text: async () => "x" })),
    );
    await mount(`
      <section data-controller="launch-modal">
        <button id="open" data-action="click->launch-modal#openModal" data-url="/x" data-name="order"></button>
        <div id="order-modal"><div id="order-body"></div></div>
      </section>`);
    $("open").click();
    await vi.waitFor(() => expect(modal.show).toHaveBeenCalled());
  });

  it("closes through the dialog it opened", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ text: async () => "x" })),
    );
    await mount(page);
    $("open").click();
    await vi.waitFor(() => expect(modal.show).toHaveBeenCalled());
    $("close").click();
    expect(modal.hide).toHaveBeenCalledTimes(1);
  });

  it("closes a dialog it did not open through the instance on the page", async () => {
    existingInstance = modal;
    await mount(`
      <div data-controller="launch-modal" id="order-modal">
        <button id="close" data-action="click->launch-modal#close"></button>
      </div>`);
    $("close").click();
    expect(modal.hide).toHaveBeenCalledTimes(1);
  });

  it("has nothing to close when no dialog was opened", async () => {
    await mount(`
      <div data-controller="launch-modal" id="order-modal">
        <button id="close" data-action="click->launch-modal#close"></button>
      </div>`);
    $("close").click();
    expect(modal.hide).not.toHaveBeenCalled();
  });
});

describe("job-order-comments-modal", () => {
  const page = `
    <div data-controller="job-order-comments-modal" id="m">
      <span data-job-order-comments-modal-target="id"></span>
      <p data-job-order-comments-modal-target="comments"></p>
      <button id="close" data-action="click->job-order-comments-modal#close"></button>
    </div>`;

  it("shows the order number and the comments with line breaks", async () => {
    await mount(page);
    const controller = application.getControllerForElementAndIdentifier(
      $("m"),
      "job-order-comments-modal",
    );
    controller.setCoHostContent({ id: "12", comments: "one\ntwo" });
    expect(document.querySelector("span").innerHTML).toBe("12");
    expect(document.querySelector("p").innerHTML).toBe("one<br>two");
  });

  it("shows the order number and comments as text, not markup", async () => {
    await mount(page);
    const controller = application.getControllerForElementAndIdentifier(
      $("m"),
      "job-order-comments-modal",
    );
    controller.setCoHostContent({
      id: "<b>1</b>",
      comments: "<img src=x onerror=alert(1)>\nnext",
    });
    expect(document.querySelector("span").querySelector("b")).toBeNull();
    expect(document.querySelector("span").textContent).toBe("<b>1</b>");
    expect(document.querySelector("p").querySelector("img")).toBeNull();
    expect(document.querySelector("p").textContent).toBe(
      "<img src=x onerror=alert(1)>next",
    );
    expect(document.querySelectorAll("p br")).toHaveLength(1);
  });

  it("opens and closes the dialog with a backdrop", async () => {
    await mount(page);
    const controller = application.getControllerForElementAndIdentifier(
      $("m"),
      "job-order-comments-modal",
    );
    controller.open();
    expect(document.body.classList.contains("modal-open")).toBe(true);
    expect($("m").classList.contains("show")).toBe(true);
    expect($("m").getAttribute("style")).toBe("display: block;");
    expect(document.querySelectorAll(".modal-backdrop")).toHaveLength(1);

    $("close").click();
    expect(document.body.classList.contains("modal-open")).toBe(false);
    expect($("m").classList.contains("show")).toBe(false);
    expect($("m").hasAttribute("style")).toBe(false);
    expect(document.querySelectorAll(".modal-backdrop")).toHaveLength(0);
  });
});

describe("launch-custom-modal", () => {
  it("hands the button's data to the comments dialog and opens it", async () => {
    await mount(`
      <div data-controller="launch-custom-modal">
        <div data-launch-custom-modal-target="jobOrderCommentsModal"
             data-controller="job-order-comments-modal" id="comments">
          <span data-job-order-comments-modal-target="id"></span>
          <p data-job-order-comments-modal-target="comments"></p>
        </div>
        <button id="go" data-action="click->launch-custom-modal#launchJobOrderCommentsModal"
                data-id="5" data-comments="a&#10;b"></button>
      </div>`);
    $("go").click();
    expect(document.querySelector("span").innerHTML).toBe("5");
    expect(document.querySelector("p").innerHTML).toBe("a<br>b");
    expect($("comments").classList.contains("show")).toBe(true);
  });
});

describe("volunteer-search", () => {
  const rows = (cls, names) =>
    names
      .map(
        (n) =>
          `<tr data-volunteer-search-target="${cls}Row"><td>${n}</td></tr>`,
      )
      .join("");
  const page = `
    <div data-controller="volunteer-search">
      <input data-volunteer-search-target="input" data-action="input->volunteer-search#filter" id="q">
      <button data-volunteer-search-target="clearButton" class="d-none" data-action="volunteer-search#clear" id="clear"></button>
      <span data-volunteer-search-target="activeCount" id="ac"></span>
      <span data-volunteer-search-target="inactiveCount" id="ic"></span>
      <div data-volunteer-search-target="activeTableContainer" id="at"><table>${rows("active", ["Ann Lee", "Bob Ray"])}</table></div>
      <div data-volunteer-search-target="activeEmpty" class="d-none" id="ae"></div>
      <div data-volunteer-search-target="inactiveTableContainer" id="it"><table>${rows("inactive", ["Cy Young"])}</table></div>
      <div data-volunteer-search-target="inactiveEmpty" class="d-none" id="ie"></div>
    </div>`;

  const search = (value) => {
    $("q").value = value;
    $("q").dispatchEvent(new Event("input"));
  };
  const hidden = (selector) =>
    [...document.querySelectorAll(selector)].map((r) =>
      r.classList.contains("d-none"),
    );

  it("hides the rows that do not match and counts the visible ones", async () => {
    await mount(page);
    search("ann");
    expect(hidden('[data-volunteer-search-target="activeRow"]')).toEqual([
      false,
      true,
    ]);
    expect(hidden('[data-volunteer-search-target="inactiveRow"]')).toEqual([
      true,
    ]);
    expect($("ac").textContent).toBe("1");
    expect($("ic").textContent).toBe("0");
    expect($("clear").classList.contains("d-none")).toBe(false);
  });

  it("shows the empty message in place of a table with no match", async () => {
    await mount(page);
    search("cy");
    expect($("ae").classList.contains("d-none")).toBe(false);
    expect($("at").classList.contains("d-none")).toBe(true);
    expect($("ie").classList.contains("d-none")).toBe(true);
    expect($("it").classList.contains("d-none")).toBe(false);
  });

  it("restores everything and the full counts for an empty search", async () => {
    await mount(page);
    search("zzz");
    search("");
    expect(hidden("tr").some(Boolean)).toBe(false);
    expect($("ac").textContent).toBe("2");
    expect($("ic").textContent).toBe("1");
    expect($("ae").classList.contains("d-none")).toBe(true);
    expect($("clear").classList.contains("d-none")).toBe(true);
  });

  it("clears the search and focuses the box", async () => {
    await mount(page);
    search("ann");
    $("clear").click();
    expect($("q").value).toBe("");
    expect(document.activeElement).toBe($("q"));
    expect(hidden("tr").some(Boolean)).toBe(false);
  });

  it("works with only the input and rows", async () => {
    await mount(`
      <div data-controller="volunteer-search">
        <input data-volunteer-search-target="input" id="q">
        <table><tr data-volunteer-search-target="activeRow"><td>Ann</td></tr></table>
      </div>`);
    const controller = application.getControllerForElementAndIdentifier(
      document.querySelector("[data-controller]"),
      "volunteer-search",
    );
    $("q").value = "x";
    controller.filter();
    expect(document.querySelector("tr").classList.contains("d-none")).toBe(
      true,
    );
  });

  it("matches without regard to case or surrounding spaces", async () => {
    await mount(page);
    search("  BOB ");
    expect(hidden('[data-volunteer-search-target="activeRow"]')).toEqual([
      true,
      false,
    ]);
    expect($("ac").textContent).toBe("1");
    expect($("clear").classList.contains("d-none")).toBe(false);
  });

  it("treats a search of only spaces as empty", async () => {
    await mount(page);
    search("   ");
    expect(hidden("tr").some(Boolean)).toBe(false);
    expect($("ac").textContent).toBe("2");
    expect($("clear").classList.contains("d-none")).toBe(true);
  });

  it("shows both empty messages when nothing matches", async () => {
    await mount(page);
    search("zzz");
    expect($("ae").classList.contains("d-none")).toBe(false);
    expect($("at").classList.contains("d-none")).toBe(true);
    expect($("ie").classList.contains("d-none")).toBe(false);
    expect($("it").classList.contains("d-none")).toBe(true);
  });

  it("counts the rows the list has now for an empty search", async () => {
    await mount(page);
    const added = document.createElement("tr");
    added.dataset.volunteerSearchTarget = "activeRow";
    added.textContent = "Dee New";
    $("at").querySelector("tr").after(added);
    search("");
    expect($("ac").textContent).toBe("3");
    search("dee");
    expect($("ac").textContent).toBe("1");
    document
      .querySelector('[data-volunteer-search-target="inactiveRow"]')
      .remove();
    search("");
    expect($("ic").textContent).toBe("0");
  });

  it("shows the empty message for a list that gained its rows after the page loaded", async () => {
    await mount(`
      <div data-controller="volunteer-search">
        <input data-volunteer-search-target="input" data-action="input->volunteer-search#filter" id="q">
        <div data-volunteer-search-target="activeTableContainer" id="at"><table><tbody id="rows"></tbody></table></div>
        <div data-volunteer-search-target="activeEmpty" class="d-none" id="ae"></div>
      </div>`);
    $("rows").innerHTML =
      `<tr data-volunteer-search-target="activeRow"><td>Ann</td></tr>`;
    search("zzz");
    expect($("ae").classList.contains("d-none")).toBe(false);
    expect($("at").classList.contains("d-none")).toBe(true);
  });

  it("never shows the empty message for a list that had no volunteers", async () => {
    await mount(`
      <div data-controller="volunteer-search">
        <input data-volunteer-search-target="input" id="q">
        <div data-volunteer-search-target="activeTableContainer" id="at"></div>
        <div data-volunteer-search-target="activeEmpty" class="d-none" id="ae"></div>
        <div data-volunteer-search-target="inactiveTableContainer" id="it"></div>
        <div data-volunteer-search-target="inactiveEmpty" class="d-none" id="ie"></div>
      </div>`);
    search("ann");
    expect($("ae").classList.contains("d-none")).toBe(true);
    expect($("at").classList.contains("d-none")).toBe(false);
    expect($("ie").classList.contains("d-none")).toBe(true);
    expect($("it").classList.contains("d-none")).toBe(false);
  });

  it("leaves an empty message alone when its table container is missing", async () => {
    await mount(`
      <div data-controller="volunteer-search">
        <input data-volunteer-search-target="input" id="q">
        <table>${rows("active", ["Ann"])}${rows("inactive", ["Cy"])}</table>
        <div data-volunteer-search-target="activeEmpty" class="d-none" id="ae"></div>
        <div data-volunteer-search-target="inactiveEmpty" class="d-none" id="ie"></div>
      </div>`);
    search("zzz");
    expect($("ae").classList.contains("d-none")).toBe(true);
    expect($("ie").classList.contains("d-none")).toBe(true);
  });

  it("leaves a table container alone when its empty message is missing", async () => {
    await mount(`
      <div data-controller="volunteer-search">
        <input data-volunteer-search-target="input" id="q">
        <div data-volunteer-search-target="activeTableContainer" id="at"><table>${rows("active", ["Ann"])}</table></div>
        <div data-volunteer-search-target="inactiveTableContainer" id="it"><table>${rows("inactive", ["Cy"])}</table></div>
      </div>`);
    search("zzz");
    expect($("at").classList.contains("d-none")).toBe(false);
    expect($("it").classList.contains("d-none")).toBe(false);
  });
});

describe("confirmation", () => {
  const button = (attrs = "") =>
    `<button id="go" disabled ${attrs} data-controller="confirmation"
             data-confirmation-message-value="Sure?"
             data-action="click->confirmation#ask">Go</button>`;

  afterEach(() => vi.unstubAllGlobals());

  const click = () => {
    const event = new Event("click", { bubbles: true, cancelable: true });
    $("go").dispatchEvent(event);
    return event;
  };

  it("enables a button that was rendered disabled once it connects", async () => {
    await mount(button());
    expect($("go").disabled).toBe(false);
  });

  it("leaves an element that cannot be disabled alone", async () => {
    await mount(
      '<a id="go" href="/x" data-controller="confirmation" data-confirmation-message-value="Go?">Go</a>',
    );
    expect($("go").hasAttribute("disabled")).toBe(false);
  });

  it("asks with its message and cancels the click when declined", async () => {
    const confirm = vi.fn(() => false);
    vi.stubGlobal("confirm", confirm);
    await mount(button());
    const listener = vi.fn();
    document.body.addEventListener("click", listener);
    const event = click();
    expect(confirm).toHaveBeenCalledWith("Sure?");
    expect(event.defaultPrevented).toBe(true);
    expect(listener).not.toHaveBeenCalled();
  });

  it("lets the click through when confirmed", async () => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => true),
    );
    await mount(button());
    expect(click().defaultPrevented).toBe(false);
  });
});
