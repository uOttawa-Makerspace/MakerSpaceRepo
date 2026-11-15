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

  it("recomputes the total in French as a price is typed", async () => {
    const total = await openModal("fr");
    const price = document.querySelector(".line-item-price");
    price.value = "1.25";
    price.dispatchEvent(new Event("input"));
    expect(total.textContent).toBe("2513,50");
  });
});
