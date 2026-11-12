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
    HOME = Table::HOME
    UNTRUSTED = Table::UNTRUSTED

    module_function

    # answer: [status, redirect path or nil]
    def acceptable?(path_spec, role, answer)
      return true if Table::ANSWERS.any? { |e| covers?(e, path_spec, role, answer) }

      status, target = answer
      return !refusal_expected?(path_spec, role) if status == 200
      return redirect_by_default?(role, target) if [302, 303].include?(status)

      false
    end

    # Entries for this role that match no route, or a route that answers
    # something the entry does not cover: { entry => [route and answer, ...] }.
    def stale_entries(answers, role)
      entries = Table::ANSWERS.select { |e| e[:roles].include?(role) }
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
      UNTRUSTED.include?(role) && Table::RESTRICTED.any? { |re, _| path_spec.match?(re) }
    end

    def redirect_by_default?(role, target)
      return target.to_s.match?(SIGN_IN) if role == :guest

      false
    end
  end
end
