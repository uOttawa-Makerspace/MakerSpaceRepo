// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

const hide = vi.fn();
const getInstance = vi.fn();
vi.mock("bootstrap", () => ({ Modal: { getInstance } }));

const { closeSaved } =
  await import("../../../app/javascript/src/calendar_dialog.js");
const { rangeSource } =
  await import("../../../app/javascript/src/range_source.js");

afterEach(() => vi.restoreAllMocks());

describe("closeSaved", () => {
  it("is marked saved while the dialog hides, and not afterwards", () => {
    const dialog = document.createElement("div");
    let markedWhileHiding;
    hide.mockImplementation(() => (markedWhileHiding = dialog.dataset.saved));
    getInstance.mockReturnValue({ hide });

    closeSaved(dialog);

    expect(getInstance).toHaveBeenCalledWith(dialog);
    expect(markedWhileHiding).toBe("true");
    expect(dialog.dataset.saved).toBeUndefined();
  });

  it("does nothing for a dialog that was never opened", () => {
    getInstance.mockReturnValue(null);
    expect(() => closeSaved(document.createElement("div"))).not.toThrow();
  });
});

describe("a range source that forgets", () => {
  it("asks the feed again for the same range after forget", async () => {
    const fetchMock = vi.fn(async () => ({ ok: true, json: async () => [1] }));
    vi.stubGlobal("fetch", fetchMock);
    const source = rangeSource(
      "x",
      "/feed",
      (rows) => rows,
      (rows) => rows,
    );
    const ask = () =>
      new Promise((resolve, reject) =>
        source.events({ startStr: "a", endStr: "b" }, resolve, reject),
      );

    await ask();
    await ask();
    expect(fetchMock).toHaveBeenCalledTimes(1);

    source.forget();
    await ask();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
