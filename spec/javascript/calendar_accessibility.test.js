import { describe, expect, it } from "vitest";

import { makeCalendarAccessible } from "../../app/javascript/src/calendar_accessibility.js";

const element = () => {
  const attributes = {};
  return {
    attributes,
    setAttribute: (name, value) => {
      attributes[name] = value;
    },
  };
};

describe("makeCalendarAccessible", () => {
  it("hides the toolbar icons and makes the scroll containers focusable", () => {
    const icon = element();
    const scroller = element();
    const root = {
      querySelectorAll: (selector) =>
        ({ '.fc-icon[role="img"]': [icon], ".fc-scroller": [scroller] })[
          selector
        ],
    };

    makeCalendarAccessible(root);

    expect(icon.attributes).toEqual({ "aria-hidden": "true" });
    expect(scroller.attributes).toEqual({ tabindex: "0" });
  });
});
