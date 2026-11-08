// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const toasts = [];
vi.mock("../../app/javascript/src/toast", () => ({
  showToast: (message, options) => toasts.push({ message, ...options }),
}));

const {
  failureText,
  pageText,
  parseBody,
  reportFailure,
  RequestFailed,
  requestJson,
  requestResult,
  requestText,
  resultError,
  serverError,
  showFailure,
} = await import("../../app/javascript/src/request_error");

const answer = (status, body, headers = {}) =>
  new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers,
  });

beforeEach(() => {
  toasts.length = 0;
  document.documentElement.dataset.requestFailed = "Reload and retry";
  document.documentElement.dataset.requestNetwork = "Unreachable";
});

describe("parseBody", () => {
  it("returns the parsed JSON", () => {
    expect(parseBody('{"error":"x"}')).toEqual({ error: "x" });
  });

  it("returns null for text that is not JSON", () => {
    expect(parseBody("<html>500</html>")).toBeNull();
    expect(parseBody("")).toBeNull();
  });
});

describe("serverError", () => {
  it("shows the server's reason followed by its reference", () => {
    expect(
      serverError(
        { error: "Order is gone", reference: "ab12cd34" },
        "fallback",
      ),
    ).toBe("Order is gone [ab12cd34]");
  });

  it("does not repeat a reference the reason already quotes", () => {
    const body = { error: "Quote reference ab12cd34.", reference: "ab12cd34" };
    expect(serverError(body, "fallback")).toBe("Quote reference ab12cd34.");
  });

  it("shows the reason alone when there is no reference", () => {
    expect(serverError({ error: "Not allowed" }, "fallback")).toBe(
      "Not allowed",
    );
  });

  it("falls back when the body has no usable reason", () => {
    expect(serverError(null, "fallback")).toBe("fallback");
    expect(serverError({ errors: ["x"] }, "fallback")).toBe("fallback");
    expect(serverError({ error: "" }, "fallback")).toBe("fallback");
    expect(serverError({ error: 500 }, "fallback")).toBe("fallback");
  });
});

describe("requestResult", () => {
  it("reads the whole answer", async () => {
    global.fetch = vi.fn(async () => ({
      ok: false,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => "{}",
    }));
    expect(await requestResult("/x", {}, "network")).toEqual({
      ok: false,
      contentType: "application/json",
      requestId: "",
      text: "{}",
    });
  });

  it("turns a rejected fetch into the translated text", async () => {
    global.fetch = vi.fn(() =>
      Promise.reject(new TypeError("Failed to fetch")),
    );
    await expect(requestResult("/x", {}, "network")).rejects.toThrow("network");
  });

  it("turns a body that cannot be read into the translated text", async () => {
    global.fetch = vi.fn(async () => ({
      ok: true,
      headers: new Headers(),
      text: () => Promise.reject(new TypeError("terminated")),
    }));
    await expect(requestResult("/x", {}, "network")).rejects.toBeInstanceOf(
      RequestFailed,
    );
  });
});

describe("failureText", () => {
  it("uses the translated message of a RequestFailed and the fallback for anything else", () => {
    expect(failureText(new RequestFailed("translated"), "fallback")).toBe(
      "translated",
    );
    expect(failureText(new TypeError("Failed to fetch"), "fallback")).toBe(
      "fallback",
    );
  });
});

it("pageText reads the layout's attribute and is empty when missing", () => {
  expect(pageText("requestFailed")).toBe("Reload and retry");
  expect(pageText("nothingHere")).toBe("");
});

describe("requestResult network text", () => {
  it("defaults to the page's translated network text", async () => {
    global.fetch = vi.fn(() =>
      Promise.reject(new TypeError("Failed to fetch")),
    );
    await expect(requestResult("/x")).rejects.toThrow("Unreachable");
  });
});

describe("resultError", () => {
  it("uses the server's reason and reference", () => {
    expect(
      resultError({
        text: '{"error":"Gone","reference":"ab12"}',
        requestId: "zzz",
      }),
    ).toBe("Gone [ab12]");
  });

  it("falls back to the page's text with the request id's first characters", () => {
    expect(resultError({ text: "<html>", requestId: "abcdef0123456789" })).toBe(
      "Reload and retry [abcdef01]",
    );
  });

  it("falls back to the page's text alone when there is no request id", () => {
    expect(resultError({ text: "", requestId: "" })).toBe("Reload and retry");
    expect(resultError({ text: "", requestId: "" }, "mine")).toBe("mine");
  });
});

describe("requestJson", () => {
  it("returns the parsed body of an OK answer, null for an empty one", async () => {
    global.fetch = vi.fn().mockResolvedValue(answer(200, { a: 1 }));
    expect(await requestJson("/x")).toEqual({ a: 1 });
    global.fetch = vi
      .fn()
      .mockResolvedValue(new Response(null, { status: 204 }));
    expect(await requestJson("/x")).toBeNull();
  });

  it("throws the server's reason for a failed answer", async () => {
    global.fetch = vi.fn().mockResolvedValue(answer(422, { error: "Taken" }));
    await expect(requestJson("/x")).rejects.toThrow(new RequestFailed("Taken"));
  });

  it("throws the page's generic text with the request id for an HTML error page", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue(
        answer(500, "<html>", { "X-Request-Id": "abcdef0123" }),
      );
    await expect(requestJson("/x")).rejects.toThrow(
      "Reload and retry [abcdef01]",
    );
  });

  it("throws for an OK answer without a JSON body only when a body is required", async () => {
    global.fetch = vi.fn(async () => answer(200, "<html>"));
    await expect(
      requestJson("/x", {}, { requireBody: true, fallback: "Not JSON" }),
    ).rejects.toThrow("Not JSON");
    expect(await requestJson("/x")).toBeNull();
  });

  it("throws the translated network text when the request fails", async () => {
    global.fetch = vi.fn(() =>
      Promise.reject(new TypeError("Failed to fetch")),
    );
    await expect(requestJson("/x")).rejects.toThrow("Unreachable");
    await expect(
      requestJson("/x", {}, { networkText: "Mine" }),
    ).rejects.toThrow("Mine");
  });
});

describe("requestText", () => {
  it("returns the text of an OK answer", async () => {
    global.fetch = vi.fn().mockResolvedValue(answer(200, "plain"));
    expect(await requestText("/x")).toBe("plain");
  });

  it("throws the reason for a failed answer", async () => {
    global.fetch = vi.fn(async () => answer(403, { error: "No" }));
    await expect(requestText("/x")).rejects.toThrow("No");
    global.fetch = vi.fn(async () => answer(403, "<html>"));
    await expect(requestText("/x", {}, { fallback: "F" })).rejects.toThrow("F");
  });
});

describe("failureText defaults and the toasts", () => {
  it("falls back to the page's generic text", () => {
    expect(failureText(new TypeError("Failed to fetch"))).toBe(
      "Reload and retry",
    );
  });

  it("toasts a server error's own message", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    reportFailure(new RequestFailed("Locker 5 is taken"));
    expect(toasts).toEqual([{ message: "Locker 5 is taken", type: "error" }]);
  });

  it("toasts the generic text for a dropped connection, never the raw error", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    reportFailure(new TypeError("Failed to fetch"));
    expect(toasts).toEqual([{ message: "Reload and retry", type: "error" }]);
  });

  it("showFailure toasts the given text as an error", () => {
    showFailure("Text");
    expect(toasts).toEqual([{ message: "Text", type: "error" }]);
  });
});
