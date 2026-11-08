import { describe, expect, it, vi } from "vitest";
import {
  failureText,
  parseBody,
  RequestFailed,
  requestResult,
  serverError,
} from "../../app/javascript/src/request_error";

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
      headers: { get: () => "application/json" },
      text: async () => "{}",
    }));
    expect(await requestResult("/x", {}, "network")).toEqual({
      ok: false,
      contentType: "application/json",
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
      headers: { get: () => "" },
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
