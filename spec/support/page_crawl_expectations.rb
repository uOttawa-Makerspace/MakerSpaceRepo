# frozen_string_literal: true

# What the page crawl (spec/requests/page_crawl_spec.rb) expects each route to
# answer, and the extra request options some routes need.
#
# A route passes when it answers:
# - 200, except for guest and regular users on /admin and /staff pages, which
#   must refuse them (listed below if one is meant to render);
# - a redirect: guests to the sign-in page, signed-in users anywhere except the
#   home page or the sign-in page (the usual "not allowed" bounce);
# - anything else only where ANSWERS lists it, with the reason.
#
# A route that should render but answers 404 because the world lacks its data
# is a crawl bug: fix the world, do not add an entry here. An entry that stops
# matching, or a route it was written for that answers something else, fails
# the crawl, so the table stays exact.
module PageCrawl
  module Expectations
    SIGN_IN = %r{\A/login\z}
    HOME = %r{\A/\z}
    ALL = PageCrawl::ROLES
    SIGNED_IN = ALL - %i[guest]
    UNTRUSTED = %i[guest regular].freeze
    RESTRICTED_AREA = %r{\A/(admin|staff)/}

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
      { path: %r{\A/sub_space_booking/(users|get_sub_space_booking)\z}, roles: %i[regular], status: :redirect, to: HOME,
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
      { path: %r{\A/(key_requests|key_certifications)(/|\z)}, roles: %i[guest regular], status: :redirect, to: HOME,
        why: "pages for staff and Teams members; anyone else is sent home" },
      { path: %r{\A/exams/:id\z}, roles: %i[guest regular], status: :redirect, to: HOME,
        why: "an exam belongs to its taker and the session's staff; anyone else is sent home" },
      { path: %r{\A/project_proposals/:id\z}, roles: %i[guest], status: :redirect, to: %r{\A/project_proposals\z},
        why: "the proposal is not public; the public list is shown instead" },

      # Redirects for every role
      { path: %r{\A/reset_password_form\z}, roles: ALL, status: :redirect, to: %r{\A/forgot_password\z},
        why: "the form needs a reset token the crawl does not have" },
      { path: %r{\A/:user_username/:id/password_entry\z}, roles: ALL, status: :redirect, to: %r{\A/[^/]+/\d+\z},
        why: "the repository has no password, so its page is shown" }
    ].freeze

    module_function

    # answer: [status, redirect path or nil]
    def acceptable?(path_spec, role, answer)
      return true if ANSWERS.any? { |e| covers?(e, path_spec, role, answer) }

      status, target = answer
      return !refusal_expected?(path_spec, role) if status == 200
      return redirect_by_default?(role, target) if [302, 303].include?(status)

      false
    end

    # Entries for this role that match no route, or a route that answers
    # something the entry does not cover: { entry => [route and answer, ...] }.
    def stale_entries(answers, role)
      entries = ANSWERS.select { |e| e[:roles].include?(role) }
      stale = entries.index_with { |e| off_routes(e, answers, role) }
      stale.reject { |_, off| off.empty? }
    end

    def off_routes(entry, answers, role)
      hits = answers.select { |path_spec, _| path_spec.match?(entry[:path]) }
      return ["matches no route"] if hits.empty?

      hits.reject { |path_spec, answer| covers?(entry, path_spec, role, answer) }
          .map { |path_spec, answer| "#{path_spec} -> #{answer.compact.join(' ')}" }
    end

    def covers?(entry, path_spec, role, answer)
      return false unless entry[:roles].include?(role) && path_spec.match?(entry[:path])

      status, target = answer
      if entry[:status] == :redirect
        [302, 303].include?(status) && target.to_s.match?(entry[:to])
      else
        status == entry[:status]
      end
    end

    def refusal_expected?(path_spec, role)
      UNTRUSTED.include?(role) && path_spec.match?(RESTRICTED_AREA)
    end

    def redirect_by_default?(role, target)
      return target.to_s.match?(SIGN_IN) if role == :guest

      !target.to_s.match?(HOME) && !target.to_s.match?(SIGN_IN)
    end
  end
end
