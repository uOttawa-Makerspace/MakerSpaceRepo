import { describe, expect, it } from "vitest";

import { makeCalendarAccessible } from "../../app/javascript/src/calendar_accessibility.js";

describe("makeCalendarAccessible", () => {
  it("hides the toolbar icons from assistive technology", () => {
    const attributes = {};
    const icon = {
      setAttribute: (name, value) => {
        attributes[name] = value;
      },
    };
    const root = {
      querySelectorAll: (selector) =>
        selector === '.fc-icon[role="img"]' ? [icon] : [],
    };

    makeCalendarAccessible(root);

    expect(attributes).toEqual({ "aria-hidden": "true" });
  });
});
