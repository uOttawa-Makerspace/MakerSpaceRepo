import { describe, expect, it } from "vitest";
import { parseBody, serverError } from "../../app/javascript/src/request_error";

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
