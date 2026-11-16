// The booking page's Stimulus controllers, started as the application starts
// them, and the attributes the views give the booking markup (index,
// _book_modal, _approve_recurring_modal, _admin), added by element id to a
// test page.
import { Application } from "@hotwired/stimulus";

const CONTROLLERS = {
  "booking-calendar": "booking_calendar_controller.js",
  "booking-modal": "booking_modal_controller.js",
  "booking-toast": "booking_toast_controller.js",
  "recurring-approval": "recurring_approval_controller.js",
  "select-all": "select_all_controller.js",
};

export async function startBookingControllers() {
  const application = Application.start();
  for (const [name, file] of Object.entries(CONTROLLERS)) {
    const module = await import(`../../../app/javascript/controllers/${file}`);
    application.register(name, module.default);
  }
  return application;
}

const modal = (target, action = "") =>
  `data-booking-modal-target="${target}"${action && ` data-action="${action}"`}`;
const part = (modes, target = "part") =>
  `data-booking-modal-target="${target}" data-modes="${modes}"`;
const request = (method, url, more = "") =>
  `data-booking-modal-method-param="${method}" data-booking-modal-url-param="${url}"${more}`;
const removal = (url) =>
  `data-action="confirmation:confirmed->booking-modal#request" ${request("DELETE", url)}`;
const DELETE_ONE = "/sub_space_booking/:id/delete/:id";

const ATTRIBUTES = {
  "booked-calendar":
    'data-controller="booking-calendar" data-booking-calendar-booking-modal-outlet="#bookModal" data-booking-calendar-booking-toast-outlet="#booking_toast"',
  booking_toast: 'data-controller="booking-toast"',
  toast_title: 'data-booking-toast-target="title"',
  toast_text: 'data-booking-toast-target="text"',
  bookModal:
    'data-controller="booking-modal" data-booking-modal-booking-calendar-outlet="#booked-calendar" data-booking-modal-booking-toast-outlet="#booking_toast"',
  bookingModalLabel: modal("title"),
  sub_space_booking_id: modal("id"),
  "book-name": modal("name"),
  "book-description": modal("description"),
  "book-start": modal("start"),
  "book-end": modal("end"),
  "end-date-validation": modal("endValidation"),
  subspace: part("edit series", "subspace part"),
  subspace_header: part("edit series"),
  "book-recurring": `${part("new", "recurring part")} data-action="change->booking-modal#toggleRecurring"`,
  "book-recurring-label": part("new"),
  "book-recurring-end": modal("recurringField recurringEnd"),
  "book-recurring-end-label": modal("recurringField"),
  "book-recurring-type": modal("recurringField recurringType"),
  "book-recurring-type-label": modal("recurringField"),
  "book-blocking": modal("blocking"),
  bookSave: `${part("new", "submit part")} data-action="booking-modal#request" ${request("POST", "/sub_space_booking")}`,
  bookUpdate: `${part("edit series", "submit part")} data-action="booking-modal#request" ${request("PATCH", "/sub_space_booking/:id/update", ' data-booking-modal-success-param="updated"')}`,
  bookDelete: `${part("edit")} ${removal(DELETE_ONE)}`,
  bookDeleteRecurringDropdown: part("series"),
  bookRecurringDeleteOne: removal(DELETE_ONE),
  bookRecurringDeleteRest: removal(
    "/sub_space_booking/:id/delete_remaining_recurring",
  ),
  bookCancel: 'data-action="booking-modal#close"',
  bookClose: 'data-action="booking-modal#close"',
  approveRecurringModal:
    'data-controller="recurring-approval" data-action="show.bs.modal->recurring-approval#fill"',
  "recurring-checkboxes": 'data-recurring-approval-target="dates"',
  recurringSelectAll:
    'data-action="recurring-approval#tick" data-recurring-approval-checked-param="true"',
  recurringSelectNone:
    'data-action="recurring-approval#tick" data-recurring-approval-checked-param="false"',
};

// The page with the views' attributes on every element whose id has some.
export function withControllers(page) {
  return page
    .replace(/id="([^"]+)"/g, (match, id) =>
      ATTRIBUTES[id] ? `${match} ${ATTRIBUTES[id]}` : match,
    )
    .replace(
      'class="flatpickr"',
      `class="flatpickr" ${modal("recurringField")}`,
    );
}

export const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
