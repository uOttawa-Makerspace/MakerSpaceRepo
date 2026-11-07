// FullCalendar draws its toolbar chevrons as <span role="img"> with no text and
// scrolls its time grid in containers that cannot take keyboard focus. The
// toolbar buttons already carry their own labels, so the chevrons are hidden
// from assistive technology and the scroll containers are made focusable.
export function makeCalendarAccessible(root) {
  root
    .querySelectorAll('.fc-icon[role="img"]')
    .forEach((icon) => icon.setAttribute("aria-hidden", "true"));
  root
    .querySelectorAll(".fc-scroller")
    .forEach((scroller) => scroller.setAttribute("tabindex", "0"));
}
