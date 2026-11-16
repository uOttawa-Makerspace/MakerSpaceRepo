// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

import { Modal } from "bootstrap";

const { closeSaved } =
  await import("../../../app/javascript/src/calendar_dialog.js");
const { rangeSource } =
  await import("../../../app/javascript/src/range_source.js");

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  document.body.replaceChildren();
});

// A Bootstrap dialog that fades in and out; under fake timers its transitions
// end only when the test runs the timers.
function fadingDialog() {
  const dialog = document.createElement("div");
  dialog.className = "modal fade";
  dialog.innerHTML = '<div class="modal-dialog"></div>';
  document.body.append(dialog);
  return dialog;
}

function openDialog(dialog) {
  Modal.getOrCreateInstance(dialog, { backdrop: false }).show();
  vi.runAllTimers();
}

describe("closeSaved", () => {
  it("closes an open dialog, marked saved while it hides and not afterwards", () => {
    vi.useFakeTimers();
    const dialog = fadingDialog();
    openDialog(dialog);
    let markedWhileHiding;
    dialog.addEventListener(
      "hide.bs.modal",
      () => (markedWhileHiding = dialog.dataset.saved),
    );

    closeSaved(dialog);
    vi.runAllTimers();

    expect(markedWhileHiding).toBe("true");
    expect(dialog.dataset.saved).toBeUndefined();
    expect(dialog.classList.contains("show")).toBe(false);
  });

  it("closes a dialog saved while it is still opening, once it has opened", () => {
    vi.useFakeTimers();
    const dialog = fadingDialog();
    Modal.getOrCreateInstance(dialog, { backdrop: false }).show();
    expect(dialog.classList.contains("show")).toBe(true);

    closeSaved(dialog);
    vi.runAllTimers();

    expect(dialog.classList.contains("show")).toBe(false);
    expect(dialog.style.display).toBe("none");
  });

  it("leaves a dialog closed before the answer came closed when it opens again", () => {
    vi.useFakeTimers();
    const dialog = fadingDialog();
    openDialog(dialog);
    Modal.getInstance(dialog).hide();
    vi.runAllTimers();

    closeSaved(dialog);
    openDialog(dialog);

    expect(dialog.classList.contains("show")).toBe(true);
  });

  it("does nothing for a dialog that was never opened", () => {
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
