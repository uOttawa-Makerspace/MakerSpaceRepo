// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const picker = vi.hoisted(() => ({ options: null }));

vi.mock("@fullcalendar/core", () => ({ Calendar: class {} }));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("tom-select", () => ({
  default: class {
    constructor(_el, options) {
      picker.options = options;
    }
  },
}));
vi.mock("flatpickr", () => ({ default: {} }));
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

beforeEach(async () => {
  document.body.innerHTML = `<select id="user_booking_select" data-min-length="3" data-hint="Type at least 3 characters."></select>`;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/sub_space_booking.js");
  document.dispatchEvent(new Event("turbo:load"));
});

describe("admin user picker", () => {
  it("only fetches from the minimum length the server reads", () => {
    expect(picker.options.shouldLoad("ab")).toBe(false);
    expect(picker.options.shouldLoad("abc")).toBe(true);
  });

  it("explains the minimum instead of reporting no results", () => {
    const el = picker.options.render.not_loading();
    expect(el.textContent).toBe("Type at least 3 characters.");
  });

  it("trusts the order and matches the server returns", () => {
    expect(picker.options.score("quokka")({ name: "Rita" })).toBe(1);
  });

  it("lists nothing once the text is cut back below the minimum", () => {
    expect(picker.options.score("ab")({ name: "Rita" })).toBe(0);
    expect(picker.options.score("")({ name: "Rita" })).toBe(0);
  });

  it("offers only the answer to the latest query when answers arrive out of order", async () => {
    const answers = {};
    global.fetch = vi.fn(
      (url) =>
        new Promise((resolve) => {
          answers[url.split("=")[1]] = (people) =>
            resolve({ json: async () => people });
        }),
    );
    const callback = vi.fn();
    const tomSelect = { clearOptions: vi.fn() };
    picker.options.load.call(tomSelect, "abc", callback);
    picker.options.load.call(tomSelect, "abcd", callback);
    answers.abcd([{ id: 2, name: "Abcd Person" }]);
    await vi.waitFor(() => expect(callback).toHaveBeenCalledTimes(1));
    answers.abc([{ id: 1, name: "Abc Person" }]);
    await vi.waitFor(() => expect(callback).toHaveBeenCalledTimes(2));
    expect(callback.mock.calls[0]).toEqual([[{ id: 2, name: "Abcd Person" }]]);
    expect(callback.mock.calls[1]).toEqual([]);
  });

  it("asks the server for the typed text and passes its answer on", async () => {
    const people = [{ id: 1, name: "Rita" }];
    global.fetch = vi.fn().mockResolvedValue({ json: async () => people });
    const callback = vi.fn();
    picker.options.load.call({ clearOptions: vi.fn() }, "a b", callback);
    await vi.waitFor(() => expect(callback).toHaveBeenCalledWith(people));
    expect(global.fetch).toHaveBeenCalledWith(
      "/sub_space_booking/users?query=a%20b",
    );
  });
});
