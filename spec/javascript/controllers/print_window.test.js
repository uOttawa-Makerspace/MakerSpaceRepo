// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { Application } from "@hotwired/stimulus";

import PrintWindow from "../../../app/javascript/controllers/print_window_controller.js";

let application;
const original = { print: window.print, close: window.close };

async function boot() {
  document.body.innerHTML = `<div data-controller="print-window">
    <button id="print" type="button" data-action="print-window#print"></button>
    <button id="close" type="button" data-action="print-window#close"></button>
  </div>`;
  application = Application.start();
  application.register("print-window", PrintWindow);
  await new Promise((resolve) => setTimeout(resolve, 0));
}

// happy-dom has no print dialog; the stubs stand in for the browser's.
function stubWindow() {
  const print = vi.fn();
  const close = vi.fn();
  Object.assign(window, { print, close });
  return { print, close };
}

afterEach(() => {
  application.stop();
  document.body.innerHTML = "";
  Object.assign(window, original);
});

describe("print-window", () => {
  it("opens the print dialog from its print button", async () => {
    const { print, close } = stubWindow();
    await boot();
    document.getElementById("print").click();
    expect(print).toHaveBeenCalledTimes(1);
    expect(close).not.toHaveBeenCalled();
  });

  it("closes the window from its close button", async () => {
    const { print, close } = stubWindow();
    await boot();
    document.getElementById("close").click();
    expect(close).toHaveBeenCalledTimes(1);
    expect(print).not.toHaveBeenCalled();
  });
});
