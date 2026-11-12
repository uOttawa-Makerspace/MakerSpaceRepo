# frozen_string_literal: true

module PageCrawl
  module Expectations
    # The data behind PageCrawl::Expectations: which answers are expected and which pages are restricted.
    module Table # rubocop:disable Metrics/ModuleLength -- a data table, one entry per expected answer
      HOME = %r{\A/\z}
      ALL = PageCrawl::ROLES
      SIGNED_IN = ALL - %i[guest]
      UNTRUSTED = %i[guest regular].freeze

      # Pages guests and regular users must not get a 200 for; a page they may
      # see is listed in ANSWERS with status 200 and a reason.
      RESTRICTED = [
        [%r{\A/(admin|staff|staff_dashboard)(/|\z)}, "admin and staff areas"],
        [%r{\A/job_orders/(admin|settings)\z}, "staff job order pages"],
        [%r{\A/printers/staff_}, "staff printer pages"],
        [%r{\A/volunteers/}, "Volunteer Program pages"],
        [%r{\A/(questions|printer_issues|key_requests|key_certifications)(/|\z)}, "staff and admin pages"],
        [%r{\A/locker_rentals/(admin|expired|assign_locker)\z}, "staff locker pages"],
        [%r{\A/project_kits/(new|populate_kit_users)\z}, "staff kit pages"],
        [%r{\A/kiosk(/|\z)}, "kiosk screens (grant_access: staff and admins)"],
        [%r{\A/rfid/get_unset_rfids\z}, "reader data (signed_in and grant_access)"],
        [%r{\A/(coupon_codes|videos|printer_types|lockers)(/|\z)}, "admin management pages"],
        [%r{\A/printers(/printer_data|/last_user_assigned_to_printer)?\z}, "admin and staff printer pages"],
        [%r{\A/announcements(/|\z)}, "staff announcement pages"],
        [%r{\A/(volunteer_tasks|volunteer_task_requests|volunteer_hours)(/|\z)}, "Volunteer Program pages"],
        [%r{\A/sub_space_booking/(users|get_sub_space_booking)\z}, "staff booking lookups"],
        [%r{\A/job_orders/:job_order_id/timeline_modal\z}, "the order's owner and staff"],
        [%r{\A/locker_rentals/:id\z}, "the renter and staff"],
        [%r{\A/proficient_projects/requests\z}, "staff project requests"]
      ].freeze

      # roles: who the entry applies to; status: an Integer, or :redirect (302 or
      # 303) with `to` matching the redirect's path; path: matches the route spec.
      ANSWERS = [
        { path: %r{\A/api/v1/(?!design_day\z|contact_infos\z)}, roles: ALL, status: 401,
          why: "the API authenticates with a bearer token, not the browser session" },
        { path: %r{\A/api/v1/(design_day|contact_infos)\z}, roles: ALL, status: 200,
          why: "public data for the staff and Design Day apps" },
        { path: %r{\A/(recede|resume|refresh)_historical_location\z}, roles: ALL, status: 404,
          why: "Turbo Native routes come after the /:user_username catch-all, which answers first (no such user)" },
        { path: %r{\A/order_items/:order_item_id/\w+_modal\z}, roles: %i[regular], status: 403,
          why: "the modal is for staff; the signed-in user does not own the order item" },
        { path: %r{\A/chat_messages\z}, roles: %i[regular], status: 403,
          why: "only the job order's owner, staff and admins read its messages; the signed-in user is not the owner" },
        { path: %r{\A/volunteers/transcript\z}, roles: %i[regular], status: 200,
          why: "volunteers' own transcript, open to any signed-in user" },
        { path: %r{\A/admin/design_day/data\z}, roles: UNTRUSTED, status: 200,
          why: "public JSON for the Design Day app, which has no session" },
        { path: %r{\A/admin/certifications/open_modal\z}, roles: %i[guest], status: 401,
          why: "a script request without a session is refused, not redirected" },

        # Redirects to the home page that are the intended refusal
        { path: %r{\A/login\z}, roles: SIGNED_IN, status: :redirect, to: HOME,
          why: "already signed in" },
        { path: %r{\A/new\z}, roles: SIGNED_IN, status: :redirect, to: HOME,
          why: "the sign-up form is for visitors" },
        { path: %r{\A/admin(?!/design_day/data\z)(/|\z)}, roles: %i[regular staff], status: :redirect, to: HOME,
          why: "the admin area is for admins" },
        { path: %r{\A/((coupon_codes|videos|printer_types|lockers)\b|printers(/printer_data)?\z|faq/(new|:id/edit)\z)},
          roles: %i[regular staff], status: :redirect, to: HOME,
          why: "management pages for admins" },
        { path: %r{\A/(job_orders/(admin|settings|:job_order_id/timeline_modal)|printer_issues)(/|\z)},
          roles: %i[regular], status: :redirect, to: HOME,
          why: "staff pages; the timeline modal is for the order's owner and staff" },
        { path: %r{\A/printers/(staff_printers(_updates)?|last_user_assigned_to_printer)\z},
          roles: %i[regular], status: :redirect, to: HOME,
          why: "the printer pages are for staff" },
        { path: %r{\A/(staff|staff_dashboard|announcements|volunteer_(tasks|task_requests|hours))(/|\z)},
          roles: %i[regular], status: :redirect, to: HOME,
          why: "staff area and Volunteer Program pages; the signed-in user is neither" },
        { path: %r{\A/volunteers/(?!transcript\z)},
          roles: %i[regular], status: :redirect, to: HOME,
          why: "staff area and Volunteer Program pages; the signed-in user is neither" },
        { path: %r{\A/sub_space_booking/(users|get_sub_space_booking)\z}, roles: %i[regular], status: :redirect,
          to: HOME,
          why: "booking lists and details are for staff and admins" },
        { path: %r{\A/sub_space_booking/:\w+/edit\z}, roles: %i[regular staff], status: :redirect, to: HOME,
          why: "only the booking's owner or an admin edits it" },
        { path: %r{\A/questions(/|\z)}, roles: %i[regular staff], status: :redirect, to: HOME,
          why: "the question bank is an admin page" },
        { path: %r{\A/announcements/:id(/edit)?\z}, roles: %i[staff], status: :redirect, to: HOME,
          why: "the world's announcement is for another audience" },
        { path: %r{\A/printers/printer_data\z}, roles: %i[admin], status: :redirect, to: HOME,
          why: "a JSON endpoint; a plain page request is sent home" },
        { path: %r{\A/admin/users/search\z}, roles: %i[admin], status: :redirect, to: HOME,
          why: "the search needs a query; without one the user is sent back" },

        # Redirects for visitors who are not asked to sign in
        { path: %r{\A/rfid/get_unset_rfids\z}, roles: %i[regular], status: :redirect, to: HOME,
          why: "reader data is for staff and admins" },
        { path: %r{\A/kiosk(/|\z)}, roles: UNTRUSTED, status: :redirect, to: HOME,
          why: "kiosk screens are for staff and admins; anyone else is sent home" },
        { path: %r{\A/(key_requests|key_certifications)(/|\z)}, roles: %i[guest regular], status: :redirect, to: HOME,
          why: "pages for staff and Teams members; anyone else is sent home" },
        { path: %r{\A/exams/:id\z}, roles: %i[guest regular], status: :redirect, to: HOME,
          why: "an exam belongs to its taker and staff; anyone else is sent home" },
        { path: %r{\A/project_proposals/:id\z}, roles: %i[guest], status: :redirect, to: %r{\A/project_proposals\z},
          why: "the proposal is not public; the public list is shown instead" },

        # Redirects to another page of the app: the controller's own check, named in the reason
        { path: %r{\A/project_kits/(new|populate_kit_users)\z}, roles: %i[regular], status: :redirect,
          to: %r{\A/project_kits\z}, why: "staff and admins add kits" },
        { path: %r{\A/job_orders/(:id|:job_order_id/(invoice|task/:id/edit))\z}, roles: %i[regular], status: :redirect,
          to: %r{\A/job_orders/new\z}, why: "the order belongs to another user" },
        { path: %r{\A/project_proposals/:id(/edit)?\z}, roles: %i[regular staff], status: :redirect,
          to: %r{\A/project_proposals\z}, why: "the proposal is not visible or editable by this user" },
        { path: %r{\A/locker_rentals/(admin|assign_locker|expired|:id)\z}, roles: %i[regular], status: :redirect,
          to: %r{\A/locker_rentals\z}, why: "staff pages, or a rental of another user" },
        { path: %r{\A/proficient_projects/(requests|:id)\z}, roles: %i[regular], status: :redirect,
          to: %r{\A/development_programs\z}, why: "staff-only list, or a project the user has no access to" },
        { path: %r{\A/proficient_projects/(new|:id/edit)\z}, roles: %i[regular staff], status: :redirect,
          to: %r{\A/proficient_projects\z}, why: "creating and editing projects is for admins" },
        { path: %r{\A/learning_area/(new|:id/edit)\z}, roles: %i[regular staff], status: :redirect,
          to: %r{\A/learning_area\z}, why: "creating and editing learning modules is for admins" },
        { path: %r{\A/:user_username/:id/edit\z}, roles: %i[regular staff], status: :redirect,
          to: %r{\A/[^/]+/[^/]+\z}, why: "only the repository's owner edits it" },
        { path: %r{\A/key_requests/:key_request_id/steps\z}, roles: %i[staff admin], status: :redirect,
          to: %r{\A/staff_dashboard\z}, why: "the key request belongs to another user" },
        { path: %r{\A/key_requests/:id\z}, roles: %i[staff], status: :redirect,
          to: %r{\A/staff_dashboard\z}, why: "the key request belongs to another user" },
        { path: %r{\A/key_requests\z}, roles: %i[staff admin], status: :redirect,
          to: %r{\A/key_requests/new\z}, why: "the user has no key request yet" },
        { path: %r{\A/key_certifications/:id\z}, roles: %i[staff], status: :redirect,
          to: %r{\A/new\.}, why: "known defect: redirects to the sign-up route (users_path) instead of the profile" },
        { path: %r{\A/staff/training_sessions/:id(/training_report)?\z}, roles: %i[staff], status: :redirect,
          to: %r{\A/staff/training_sessions/new\z}, why: "the session belongs to another staff member" },
        { path: %r{\A/staff_dashboard/user_profile\z}, roles: %i[staff admin], status: :redirect,
          to: %r{\A/[^/]+\z}, why: "looks the username up and sends the staff member to the profile" },

        # Redirects for every role
        { path: %r{\A/reset_password_form\z}, roles: ALL, status: :redirect, to: %r{\A/forgot_password\z},
          why: "the form needs a reset token the crawl does not have" },
        { path: %r{\A/:user_username/:id/password_entry\z}, roles: ALL, status: :redirect, to: %r{\A/[^/]+/\d+\z},
          why: "the repository has no password, so its page is shown" }
      ].freeze
    end
  end
end
