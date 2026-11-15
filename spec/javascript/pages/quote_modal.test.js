// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

// The staff quote modal's running total, written in the page's language.
const MODAL = `
<div id="quote-modal">
  <div class="card">
    <input class="money-input base-fee" value="10">
    <input class="service-qty" value="2.5">
    <input class="money-input service-price" value="1000.1">
    <input class="money-input option-price" value="2">
  </div>
  <div class="line-item"><input class="money-input line-item-price" value="0.4"></div>
  <span id="quote-total-value">0.00</span>
</div>`;

async function openModal(lang, body = MODAL) {
  document.documentElement.setAttribute("lang", lang);
  document.body.innerHTML = body;
  vi.resetModules();
  await import("../../../app/javascript/entrypoints/quote_modal.js");
  return document.getElementById("quote-total-value");
}

afterEach(() => {
  document.documentElement.removeAttribute("lang");
  document.body.innerHTML = "";
});

describe("quote modal total", () => {
  it("writes the total with a decimal point on an English page", async () => {
    expect((await openModal("en")).textContent).toBe("2512.65");
  });

  it("writes the total with a decimal comma on a French page", async () => {
    expect((await openModal("fr")).textContent).toBe("2512,65");
  });

  it("writes an empty quote as 0.00 in English and 0,00 in French", async () => {
    const empty = `<div id="quote-modal"><span id="quote-total-value"></span></div>`;
    expect((await openModal("en", empty)).textContent).toBe("0.00");
    expect((await openModal("fr", empty)).textContent).toBe("0,00");
  });

  it("writes the total in English on a page without a language", async () => {
    expect((await openModal("")).textContent).toBe("2512.65");
  });

  // One line item holds the whole total, or a quantity times a price.
  const single = (price) =>
    `<div id="quote-modal"><div class="line-item"><input class="line-item-price" value="${price}"></div>` +
    `<span id="quote-total-value"></span></div>`;
  const product = (qty, price) =>
    `<div id="quote-modal"><div class="card"><input class="service-qty" value="${qty}">` +
    `<input class="service-price" value="${price}"></div><span id="quote-total-value"></span></div>`;
  const cases = [
    ["2.675", single("2.675"), 2.675],
    ["1.005", single("1.005"), 1.005],
    ["1.5 x 1.785", product("1.5", "1.785"), 1.5 * 1.785],
    ["0", single("0"), 0],
    ["-3.335", single("-3.335"), -3.335],
    ["1234.5", single("1234.5"), 1234.5],
    ["1e400", single("1e400"), Infinity],
  ];

  it.each(cases)(
    "rounds %s like toFixed on an English page",
    async (_name, body, value) => {
      expect((await openModal("en", body)).textContent).toBe(value.toFixed(2));
    },
  );

  it.each(cases)(
    "rounds %s like toFixed on a French page, with a comma",
    async (_name, body, value) => {
      expect((await openModal("fr", body)).textContent).toBe(
        value.toFixed(2).replace(".", ","),
      );
    },
  );

  it("keeps the rounding of a half cent the same in both languages", async () => {
    expect((await openModal("en", single("2.675"))).textContent).toBe("2.67");
    expect((await openModal("fr", single("1.005"))).textContent).toBe("1,00");
    expect((await openModal("fr", single("1234.5"))).textContent).toBe(
      "1234,50",
    );
  });

  it("recomputes the total in French as a price is typed", async () => {
    const total = await openModal("fr");
    const price = document.querySelector(".line-item-price");
    price.value = "1.25";
    price.dispatchEvent(new Event("input"));
    expect(total.textContent).toBe("2513,50");
  });
});
