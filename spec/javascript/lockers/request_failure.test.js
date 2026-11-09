// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const toasts = [];
vi.mock("../../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

const { ServerError, rejectFailedResponse, showRequestFailure } =
  await import("../../../app/javascript/src/request_failure.js");

const response = (status, body, headers = {}) =>
  new Response(body === undefined ? "<html></html>" : JSON.stringify(body), {
    status,
    headers,
  });

describe("rejectFailedResponse", () => {
  beforeEach(() => {
    toasts.length = 0;
    document.body.innerHTML = "";
  });

  it("does nothing for an OK response", async () => {
    await expect(rejectFailedResponse(response(204))).resolves.toBeUndefined();
  });

  it("throws the server's error message", async () => {
    await expect(
      rejectFailedResponse(response(422, { error: "Specifier is taken" })),
    ).rejects.toThrow(new ServerError("Specifier is taken"));
  });

  it("falls back to the page's generic text when the body has no error", async () => {
    document.body.innerHTML = '<table data-request-failed="Reload"></table>';
    await expect(
      rejectFailedResponse(response(422, { specifier: ["is taken"] })),
    ).rejects.toThrow("Reload");
  });

  it("adds the request id when an HTML error page carries one", async () => {
    document.body.innerHTML = '<table data-request-failed="Reload"></table>';
    await expect(
      rejectFailedResponse(
        response(500, undefined, { "X-Request-Id": "abcdef0123456789" }),
      ),
    ).rejects.toThrow("Reload [abcdef01]");
  });

  it("uses the built-in English text when the page has none", async () => {
    await expect(rejectFailedResponse(response(500))).rejects.toThrow(
      "could not be saved",
    );
  });
});

describe("showRequestFailure", () => {
  beforeEach(() => {
    toasts.length = 0;
    document.body.innerHTML = '<table data-request-failed="Reload"></table>';
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  it("toasts a server error's own message", () => {
    showRequestFailure(
      new ServerError("Locker 5 is taken (reference 1a2b3c4d)"),
    );
    expect(toasts).toEqual([
      { message: "Locker 5 is taken (reference 1a2b3c4d)", type: "error" },
    ]);
  });

  it("does not log a server error, which is an expected refusal already shown", () => {
    showRequestFailure(new ServerError("Locker 5 is taken"));
    expect(console.error).not.toHaveBeenCalled();
  });

  it("logs an error that is not a server error, since its text is not shown", () => {
    const error = new TypeError("Failed to fetch");
    showRequestFailure(error);
    expect(console.error).toHaveBeenCalledWith(error);
  });

  it("toasts the generic text for a dropped connection, never the raw error", () => {
    showRequestFailure(new TypeError("Failed to fetch"));
    expect(toasts).toEqual([{ message: "Reload", type: "error" }]);
  });
});
