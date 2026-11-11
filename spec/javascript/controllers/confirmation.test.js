// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";
import Confirmation from "../../../app/javascript/controllers/confirmation_controller.js";

let application;
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => {
  application?.stop();
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

async function mount() {
  document.body.innerHTML = `<button id="b" disabled data-controller="confirmation"
    data-action="click->confirmation#ask" data-confirmation-message-value="Sure?"></button>`;
  application = Application.start();
  application.register("confirmation", Confirmation);
  await settle();
  const button = document.getElementById("b");
  const confirmed = vi.fn();
  const clicked = vi.fn();
  button.addEventListener("confirmation:confirmed", confirmed);
  button.addEventListener("click", clicked);
  return { button, confirmed, clicked };
}

describe("confirmation", () => {
  it("enables the element and announces an accepted prompt", async () => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => true),
    );
    window.confirm = confirm;
    const { button, confirmed } = await mount();
    expect(button.disabled).toBe(false);
    button.click();
    expect(confirm).toHaveBeenCalledWith("Sure?");
    expect(confirmed).toHaveBeenCalledTimes(1);
  });

  it("announces nothing and stops the click when declined", async () => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => false),
    );
    window.confirm = confirm;
    const { button, confirmed, clicked } = await mount();
    button.click();
    expect(confirmed).not.toHaveBeenCalled();
    expect(clicked).not.toHaveBeenCalled();
  });
});
