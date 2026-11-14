// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const instances = [];
vi.mock("tom-select", () => ({
  default: class {
    constructor(selector, options) {
      this.selector = selector;
      this.options = options;
      instances.push(this);
    }
  },
}));
vi.mock("flatpickr", () => ({ default: {} }));

// The real flatpickr module adds this method to every element when imported.
const pickers = [];
HTMLElement.prototype.flatpickr = function (options) {
  const picker = { element: this, options, clear: vi.fn() };
  pickers.push(picker);
  return picker;
};

await import("../../../app/javascript/entrypoints/keys.js");

const $ = (id) => document.getElementById(id);

// The page script runs once per full page load, on DOMContentLoaded.
function load(html) {
  document.body.innerHTML = html;
  document.dispatchEvent(new Event("DOMContentLoaded"));
}

function change(id, value) {
  $(id).value = value;
  $(id).dispatchEvent(new Event("change"));
}

beforeEach(() => {
  instances.length = 0;
  pickers.length = 0;
});

afterEach(() => {
  document.body.innerHTML = "";
});

describe("keys page script", () => {
  it("does nothing on a page without any of its fields", () => {
    expect(() => load("<p>nothing here</p>")).not.toThrow();
    expect(instances).toEqual([]);
    expect(pickers).toEqual([]);
  });

  describe("deposit return date", () => {
    const html = `
      <input id="deposit-return-date">
      <button id="deposit-return-date-clear"></button>`;

    it("turns the field into a date-only picker", () => {
      load(html);
      expect(pickers).toHaveLength(1);
      expect(pickers[0].element).toBe($("deposit-return-date"));
      // the page locale (flatpickrOptions) adds its own keys next to these
      expect(pickers[0].options).toMatchObject({
        enableTime: false,
        noCalendar: false,
        dateFormat: "Y-m-d",
      });
    });

    it("clears the picker when the clear button is clicked", () => {
      load(html);
      expect(pickers[0].clear).not.toHaveBeenCalled();
      $("deposit-return-date-clear").click();
      expect(pickers[0].clear).toHaveBeenCalledTimes(1);
    });

    it("keeps the picker and sets up the rest of the page without the clear button", () => {
      load(
        `<input id="deposit-return-date"><select id="space-select"></select>`,
      );
      expect(pickers).toHaveLength(1);
      expect(instances.map((i) => i.selector)).toEqual(["#space-select"]);
    });
  });

  describe("searchable selects", () => {
    const html = `
      <select id="supervisor-select"></select>
      <div><select id="space-select"></select></div>
      <select id="key-request-select"></select>`;

    it("builds a name-searchable widget for supervisor, space and key request", () => {
      load(html);
      expect(instances.map((i) => i.selector)).toEqual([
        "#supervisor-select",
        "#space-select",
        "#key-request-select",
      ]);
      for (const instance of instances) {
        expect(instance.options).toEqual({
          searchField: ["name"],
          valueField: "id",
          labelField: "name",
          maxOptions: null,
          searchOnKeyUp: true,
        });
      }
    });

    it("skips a select that already has a widget", () => {
      document.body.innerHTML = html;
      $("supervisor-select").tomselect = {};
      $("key-request-select").tomselect = {};
      document.dispatchEvent(new Event("DOMContentLoaded"));
      expect(instances.map((i) => i.selector)).toEqual(["#space-select"]);
    });
  });

  describe("status and notes", () => {
    const html = `
      <select id="status-select">
        <option value="unknown">Unknown</option>
        <option value="inventory">Inventory</option>
        <option value="lost">Lost</option>
      </select>
      <div id="notes-container"></div>`;

    it("leaves the notes as rendered until the status changes", () => {
      load(html);
      expect($("notes-container").style.display).toBe("");
    });

    it("hides the notes for inventory and shows them for any other status", () => {
      load(html);
      change("status-select", "inventory");
      expect($("notes-container").style.display).toBe("none");
      change("status-select", "lost");
      expect($("notes-container").style.display).toBe("block");
    });

    it("ignores status changes when there is no notes box", () => {
      load(
        `<select id="status-select"><option value="inventory"></option></select>`,
      );
      expect(() => change("status-select", "inventory")).not.toThrow();
    });
  });

  describe("key type", () => {
    const html = `
      <select id="key-type-select">
        <option value="regular">Regular</option>
        <option value="keycard">Keycard</option>
      </select>
      <div id="space-wrap"><select id="space-select"></select></div>
      <div id="code-wrap"><input id="custom-keycode"></div>`;

    it("shows the space for a regular key and the keycode for any other type", () => {
      load(html);
      change("key-type-select", "keycard");
      expect($("space-wrap").style.display).toBe("none");
      expect($("code-wrap").style.display).toBe("block");
      change("key-type-select", "regular");
      expect($("space-wrap").style.display).toBe("block");
      expect($("code-wrap").style.display).toBe("none");
    });

    it("toggles the keycode on a page without the space select", () => {
      load(`
        <select id="key-type-select"><option value="regular"></option><option value="keycard"></option></select>
        <div id="code-wrap"><input id="custom-keycode"></div>`);
      change("key-type-select", "keycard");
      expect($("code-wrap").style.display).toBe("block");
    });

    it("toggles the space on a page without the keycode field", () => {
      load(`
        <select id="key-type-select"><option value="regular"></option><option value="keycard"></option></select>
        <div id="space-wrap"><select id="space-select"></select></div>`);
      change("key-type-select", "keycard");
      expect($("space-wrap").style.display).toBe("none");
    });
  });

  describe("printing", () => {
    beforeEach(() => {
      vi.stubGlobal("print", vi.fn());
    });

    it("prints straight away when there are no certificate frames", () => {
      load(`<button id="print-button"></button>`);
      $("print-button").click();
      expect(window.print).toHaveBeenCalledTimes(1);
    });

    describe("with certificate frames", () => {
      const html = `
        <button id="print-button"></button>
        <iframe class="key-cert-iframe" src="about:blank#a"></iframe>
        <iframe class="key-cert-iframe" src="about:blank#b"></iframe>`;
      const frames = () => [...document.querySelectorAll(".key-cert-iframe")];
      const loaded = (frame) => frame.dispatchEvent(new Event("load"));

      beforeEach(() => {
        vi.useFakeTimers();
        load(html);
      });

      it("does not print when the frames load before the button is clicked", () => {
        frames().forEach(loaded);
        vi.advanceTimersByTime(5000);
        expect(window.print).not.toHaveBeenCalled();
      });

      it("reloads each frame from its own address when the button is clicked", () => {
        const set = frames().map((frame) =>
          vi.spyOn(frame, "src", "set").mockImplementation(() => {}),
        );
        $("print-button").click();
        expect(set[0]).toHaveBeenCalledWith("about:blank#a");
        expect(set[1]).toHaveBeenCalledWith("about:blank#b");
        expect(window.print).not.toHaveBeenCalled();
      });

      it("prints one second after the last frame has loaded again", () => {
        frames().forEach((frame) =>
          vi.spyOn(frame, "src", "set").mockImplementation(() => {}),
        );
        loaded(frames()[0]);
        $("print-button").click();
        loaded(frames()[0]);
        vi.advanceTimersByTime(5000);
        expect(window.print).not.toHaveBeenCalled();
        loaded(frames()[1]);
        vi.advanceTimersByTime(999);
        expect(window.print).not.toHaveBeenCalled();
        vi.advanceTimersByTime(1);
        expect(window.print).toHaveBeenCalledTimes(1);
      });

      it("does not print again for a load after the count is reached", () => {
        frames().forEach((frame) =>
          vi.spyOn(frame, "src", "set").mockImplementation(() => {}),
        );
        $("print-button").click();
        frames().forEach(loaded);
        loaded(frames()[0]);
        vi.advanceTimersByTime(2000);
        expect(window.print).toHaveBeenCalledTimes(1);
      });

      it("counts the loads again from zero on each click", () => {
        frames().forEach((frame) =>
          vi.spyOn(frame, "src", "set").mockImplementation(() => {}),
        );
        $("print-button").click();
        frames().forEach(loaded);
        vi.advanceTimersByTime(1000);
        $("print-button").click();
        loaded(frames()[0]);
        vi.advanceTimersByTime(2000);
        expect(window.print).toHaveBeenCalledTimes(1);
        loaded(frames()[1]);
        vi.advanceTimersByTime(1000);
        expect(window.print).toHaveBeenCalledTimes(2);
      });
    });
  });
});
