import { Controller } from "@hotwired/stimulus";

// A Stimulus controller whose target, value and outlet accessors (which
// Stimulus defines at runtime) the type checker takes as any.
export const AccessorController =
  /** @type {new () => Controller<HTMLElement> & Record<string, any>} */ (
    /** @type {unknown} */ (Controller)
  );
