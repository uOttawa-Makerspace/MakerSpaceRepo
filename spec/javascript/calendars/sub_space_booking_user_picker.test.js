// @vitest-environment happy-dom
// Drives the real Tom Select: the picker lists only the server's answer for the text now in the box.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@fullcalendar/core", () => ({ Calendar: class {} }));
vi.mock("@fullcalendar/interaction", () => ({ default: {} }));
vi.mock("@fullcalendar/timegrid", () => ({ default: {} }));
vi.mock("@fullcalendar/list", () => ({ default: {} }));
vi.mock("flatpickr", () => ({ default: {} }));
vi.mock("bootstrap", () => ({
  Toast: { getOrCreateInstance: () => ({ show() {} }) },
}));
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));

const RITA = { id: 1, name: "Rita Requester" };
const BOB = { id: 2, name: "Bob Brown" };

let picker;
let pending;

const names = () => Object.values(picker.options).map((o) => o.name);

function type(text) {
  picker.control_input.value = text;
  picker.control_input.dispatchEvent(new Event("input"));
}

// answers a pending fetch by its query
function answer(query, people, { ok = true } = {}) {
  pending[query]({ ok, json: async () => people });
}

async function settle() {
  await vi.advanceTimersByTimeAsync(1000);
}

beforeEach(async () => {
  vi.useFakeTimers();
  pending = {};
  global.fetch = vi.fn(
    (url) =>
      new Promise((resolve) => {
        pending[decodeURIComponent(url.split("query=")[1])] = resolve;
      }),
  );
  document.body.innerHTML = `<form><select id="user_booking_select" data-min-length="3" data-hint="Type at least 3 characters."></select></form>`;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/sub_space_booking.js");
  document.dispatchEvent(new Event("turbo:load"));
  picker = document.getElementById("user_booking_select").tomSelect;
});

afterEach(() => vi.useRealTimers());

describe("admin user picker", () => {
  it("lists the server's answer for the typed text, matches by username included", async () => {
    type("quokka");
    await settle();
    answer("quokka", [RITA]);
    await settle();
    expect(names()).toEqual(["Rita Requester"]);
  });

  it("does not fetch below the minimum length", async () => {
    type("ri");
    await settle();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("lists nothing when a loaded text is cut below the minimum, down to empty", async () => {
    type("rit");
    await settle();
    answer("rit", [RITA]);
    await settle();
    type("ri");
    expect(names()).toEqual([]);
    type("rit");
    type("");
    expect(names()).toEqual([]);
  });

  it("lists nothing when the box is emptied while a delayed lookup is on its way", async () => {
    type("rit");
    await vi.advanceTimersByTimeAsync(350);
    type("");
    await settle();
    if (pending.rit) answer("rit", [RITA, BOB]);
    await settle();
    expect(names()).toEqual([]);
  });

  it("lists nothing when the text is cut below the minimum while a delayed lookup is on its way", async () => {
    type("rit");
    await vi.advanceTimersByTimeAsync(350);
    type("ri");
    await settle();
    if (pending.rit) answer("rit", [RITA, BOB]);
    await settle();
    expect(names()).toEqual([]);
  });

  it("drops the old answer as soon as the text changes, before the new one arrives", async () => {
    type("abc");
    await settle();
    answer("abc", [RITA]);
    await settle();
    type("abx");
    expect(names()).toEqual([]);
  });

  it("ignores the answer to an older text when a newer one is in the box", async () => {
    type("abc");
    await settle();
    type("abcd");
    await settle();
    answer("abcd", [BOB]);
    answer("abc", [RITA]);
    await settle();
    expect(names()).toEqual(["Bob Brown"]);
  });

  it("lists nothing from an error response", async () => {
    type("rit");
    await settle();
    answer("rit", [RITA], { ok: false });
    await settle();
    expect(names()).toEqual([]);
  });

  it("lists nothing under an emptied box after a selection and reopen", async () => {
    type("rit");
    await settle();
    answer("rit", [RITA, BOB]);
    await settle();
    picker.addItem("1");
    picker.close();
    picker.open();
    expect(names()).toEqual(["Rita Requester"]);
  });
});
