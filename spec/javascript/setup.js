import { afterEach, vi } from "vitest";

// Fake timers never outlive the example that turned them on, even when it fails.
afterEach(() => {
  vi.useRealTimers();
});
