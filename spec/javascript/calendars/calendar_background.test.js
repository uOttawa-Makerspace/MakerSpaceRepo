// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import {
  applyEventBackground,
  isHexColour,
} from "../../../app/javascript/src/calendar_background.js";

function styled(background) {
  const el = document.createElement("div");
  applyEventBackground(el, background);
  return el.getAttribute("style");
}

describe("applyEventBackground", () => {
  it("applies a hex colour", () => {
    expect(styled("#3788d8")).toBe("background: #3788d8");
  });

  it("applies a staff colour gradient, with or without the draft opacity", () => {
    const gradient =
      "linear-gradient(to right, #e6194b 0.0%, #e6194b 50.0%, #bbb 50.0%, #bbb 100.0%);";
    expect(styled(gradient)).toBe(`background: ${gradient}`);
    expect(styled(`${gradient} opacity: 0.8;`)).toBe(
      `background: ${gradient} opacity: 0.8;`,
    );
  });

  it.each([
    undefined,
    null,
    "",
    "red",
    "red;background:url(https://example.test/x)",
    "linear-gradient(to right, red 0.0%, red 100.0%);",
    "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);background:url(x)",
    "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);\nposition:fixed",
  ])("ignores %j", (background) => {
    expect(styled(background)).toBeNull();
  });
});

describe("isHexColour", () => {
  it.each(["#fff", "#E6194B", "#3788d8"])("accepts %s", (colour) => {
    expect(isHexColour(colour)).toBe(true);
  });

  it.each([
    undefined,
    null,
    5,
    "",
    "red",
    "#ff",
    "#ffff",
    "#gggggg",
    "#fff;x",
    "#fff\n",
  ])("rejects %j", (colour) => {
    expect(isHexColour(colour)).toBe(false);
  });
});
