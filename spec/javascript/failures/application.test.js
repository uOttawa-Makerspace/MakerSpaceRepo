// @vitest-environment happy-dom
// What application.js tells the user when changing the space or saving an exam answer fails.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { answerWith, dropConnection, flush, reset, toasts } from "./support.js";

vi.mock("trix", () => ({}));
for (const name of [
  "validation",
  "direct_uploads",
  "effects",
  "forms",
  "header",
  "photo_gallery",
  "requests",
  "settings",
  "sorting",
  "tabledata",
  "accordion-load",
  "clipboard",
  "theme",
]) {
  vi.doMock(`../../../app/javascript/src/${name}`, () => ({}));
}
vi.mock("../../../app/javascript/src/csrf", () => ({ csrfHeaders: (h) => h }));
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

await import("../../../app/javascript/entrypoints/application.js");

beforeEach(() => {
  reset();
  document.body.innerHTML = '<input id="set_space_id" value="3">';
});

describe("window.setSpace", () => {
  it("shows the server's reason when the change is refused", async () => {
    global.fetch = answerWith(422, { error: "Space is closed" });
    await window.setSpace();
    expect(toasts).toEqual([{ message: "Space is closed", type: "error" }]);
  });

  it("shows the generic text with the request reference when the answer has no reason", async () => {
    global.fetch = answerWith(500, "{}", {
      "X-Request-Id": "0123456789abcdef",
    });
    await window.setSpace();
    expect(toasts).toEqual([
      { message: "Reload and retry [01234567]", type: "error" },
    ]);
  });

  it("shows the translated network text when the connection drops", async () => {
    global.fetch = dropConnection();
    await window.setSpace();
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });
});

describe("window.examResponse", () => {
  it("shows nothing when the answer is saved", async () => {
    global.fetch = answerWith(200, {});
    await window.examResponse(1, 2);
    await flush();
    expect(toasts).toEqual([]);
  });

  it("tells the student when the answer was refused", async () => {
    global.fetch = answerWith(403, "");
    await window.examResponse(1, 2);
    expect(toasts).toEqual([{ message: "Reload and retry", type: "error" }]);
  });

  it("tells the student when the connection drops", async () => {
    global.fetch = dropConnection();
    await window.examResponse(1, 2);
    expect(toasts).toEqual([{ message: "Unreachable", type: "error" }]);
  });
});
