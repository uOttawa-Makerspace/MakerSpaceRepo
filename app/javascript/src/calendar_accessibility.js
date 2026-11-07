// FullCalendar draws its toolbar chevrons as <span role="img"> with no text.
// The toolbar buttons already carry their own labels, so the chevrons are
// hidden from assistive technology. (The time grid scroll container is left
// alone: giving it a tabindex breaks the grid roles FullCalendar sets on its
// table, which axe then reports as aria-required-children.)
export function makeCalendarAccessible(root) {
  root
    .querySelectorAll('.fc-icon[role="img"]')
    .forEach((icon) => icon.setAttribute("aria-hidden", "true"));
}
