# frozen_string_literal: true

module User::UoengConcern
  extend ActiveSupport::Concern
  include ApplicationHelper

  UpstreamError = Class.new(StandardError)
  # Raised by the shape check; its message is fixed text, unlike a parser error,
  # whose message quotes part of the body.
  UnexpectedShape = Class.new(JSON::ParserError)

  # Results that carry no answer about the user. :unavailable means the
  # upstream failed in a way that may pass (timeout, refused connection, 5xx),
  # so asking again later can succeed; :unknown means asking again will not
  # help (other statuses, a malformed body, nothing to look the user up by);
  # :mismatch means the answer is about a student number other than the one on
  # the account, so it says nothing about this user.
  NO_ANSWER = %i[unknown unavailable mismatch].freeze

  class_methods do
    # #shown_faculty in SQL, for a query that left-joins users to uoeng_profiles: the uOEng faculty
    # when there is one, otherwise the user's own.
    def shown_faculty_sql
      Arel.sql("COALESCE(NULLIF(uoeng_profiles.faculty, ''), users.faculty)")
    end

    # The users with their shown faculty read in the same query, so #shown_faculty needs no
    # further one.
    def with_shown_faculty
      left_joins(:uoeng_profile).select(arel_table[Arel.star], shown_faculty_sql.as("shown_faculty"))
    end

    # { shown faculty => number of users }, in one query.
    def count_by_shown_faculty
      left_joins(:uoeng_profile).group(shown_faculty_sql).count
    end
  end

  included do
    has_one :uoeng_profile, dependent: :destroy

    # Verify if user qualifies for a faculty membership. Returns the granted
    # membership, nil when the user is not engineering (any active faculty
    # membership is revoked), or :unknown / :unavailable / :mismatch when the
    # upstream gave no answer about this user (see NO_ANSWER): then the stored memberships are left
    # exactly as they are. After the grant or revoke, the answer is kept in the
    # user's uOEng record (see #record_uoeng_answer!).
    def validate_uoeng_membership(card_number: nil, space: nil)
      faculty_tier = MembershipTier.find_by!(title_en: "Faculty membership")

      details = uoeng_answer(card_number: card_number, space: space)
      return details if NO_ANSWER.include?(details)

      outcome = if engineering?(details, card_number, space)
                  grant_faculty_membership(faculty_tier)
                else
                  revoke_faculty_memberships(faculty_tier, card_number: card_number, space: space)
                end
      record_uoeng_answer!(details) if details
      outcome
    end

    # Only staff may run the faculty membership check for a user from the profile.
    def membership_checkable_by?(staff)
      staff.staff?
    end

    # Whether uOEng can be asked about this user: by student number, or by a
    # uOttawa email address.
    def uoeng_queryable?
      student_id.present? || email.to_s.ends_with?("@uottawa.ca")
    end

    # Keeps what uOEng said about this user (student number, faculty, program code, level,
    # full-time and current-semester status) in the user's uOEng record, replacing the previous
    # answer. The user's own profile fields are left as they are.
    def record_uoeng_answer!(answer)
      UoengProfile.record!(self, answer, source: uoeng_lookup_source)
    end

    # The faculty to show: the one uOEng states, when it maps to a faculty the app knows, otherwise
    # the one on the profile. A user loaded through .with_shown_faculty already carries it.
    def shown_faculty
      return self[:shown_faculty] if has_attribute?(:shown_faculty)

      uoeng_profile&.faculty.presence || faculty
    end

    def active_faculty_membership_count
      memberships.active.joins(:membership_tier).where(membership_tiers: { title_en: "Faculty membership" }).count
    end

    private

    def grant_faculty_membership(faculty_tier)
      memberships.active.find_or_create_by(
        membership_tier: faculty_tier,
        status: :paid,
        end_date: end_of_this_semester
      )
    end

    def revoke_faculty_memberships(faculty_tier, card_number:, space:)
      # Load once into memory to eliminate redundant COUNT and PLUCK queries
      revoked_records = memberships.active.where(membership_tier_id: faculty_tier.id).to_a

      if revoked_records.present?
        TapBoxLog.log_membership_revocation(
          user: self,
          revoked_count: revoked_records.size,
          revoked_ids: revoked_records.map(&:id),
          card_number: card_number,
          space: space
        )

        memberships.where(id: revoked_records.map(&:id)).update_all(status: :revoked)
        Rails.logger.info "Revoked #{revoked_records.size} faculty membership(s) for user id #{id}"
      end
      nil
    end

    # The checked answer about this user (a Hash), or :unknown / :unavailable /
    # :mismatch when there is no usable answer (a user who cannot be looked up is
    # logged and :unknown). nil in the test environment, where nothing is asked.
    def uoeng_answer(card_number:, space:)
      return if Rails.env.test?

      details = uoeng_details(card_number: card_number, space: space)
      return details if details

      TapBoxLog.log_no_queryable_identifier(user: self, card_number: card_number, space: space)
      :unknown
    end

    # Whether the answer says the user is an engineering student. In the test
    # environment (no answer) the faculty column is compared instead.
    def engineering?(details, card_number, space)
      return faculty == "Engineering" if details.nil?

      is_fulltime_eng = details["student_this_semester"] && details["faculty"] == "GENIE"
      enrolled_gng = details["courses_enrolled"]&.any? { |course| course.include?("GNG") }
      result = is_fulltime_eng || enrolled_gng

      unless result
        TapBoxLog.log_not_engineering(user: self, api_details: details, card_number: card_number, space: space)
      end

      detect_name_mismatch(details, card_number, space)
      result.present?
    end

    # The parsed answer (a Hash), false when the user cannot be looked up, or
    # :unavailable when the upstream timed out, refused the connection or
    # answered 5xx, or :unknown when it answered another non-200 status or sent
    # a body that does not have the expected shape.
    def uoeng_details(card_number: nil, space: nil)
      creds = Rails.application.credentials.dig(Rails.env.to_sym, :uoeng) || {}

      return false unless uoeng_queryable?

      url = uoeng_lookup_source == "student_number" ? "#{creds[:query_by_id]}#{student_id}" : "#{creds[:query_by_email]}#{email}"

      fetch_uoeng_details(url, creds[:student_information_key], card_number, space)
    end

    # How uOEng is asked about this user: by the student number when there is one, else by email.
    def uoeng_lookup_source
      student_id.present? ? "student_number" : "email"
    end

    def fetch_uoeng_details(url, key, card_number, space)
      api_start = Time.current
      response = Excon.get(url, headers: { Authorization: "Bearer #{key}" }, read_timeout: 15, connect_timeout: 10)
      elapsed = ((Time.current - api_start) * 1000).round(1)

      TapBoxLog.log_slow_api(user: self, elapsed_ms: elapsed, card_number: card_number, space: space) if elapsed > 5000
      return uoeng_http_failure(response, elapsed, card_number, space) if response.status != 200

      parsed = JSON.parse(response.body)
      raise UnexpectedShape, "unexpected answer shape" unless expected_uoeng_shape?(parsed)

      checked_uoeng_answer(parsed, card_number, space)
    rescue Excon::Error::Timeout => e
      elapsed = ((Time.current - api_start) * 1000).round(1)
      TapBoxLog.log_api_timeout(user: self, elapsed_ms: elapsed, exception: e, card_number: card_number, space: space)
      uoeng_no_answer(e, :unavailable)
    rescue JSON::ParserError => e
      TapBoxLog.log_api_bad_json(user: self, exception: e, response: response, card_number: card_number, space: space)
      uoeng_unknown(UpstreamError.new("uOEng answer: #{TapBoxLog.bad_json_reason(e)}"))
    rescue Excon::Error => e
      TapBoxLog.log_engineering_check_error(user: self, exception: e, card_number: card_number, space: space)
      uoeng_no_answer(e, :unavailable)
    end

    # Every field the check reads may be missing or null, but when present it
    # must have the expected type.
    def expected_uoeng_shape?(parsed)
      parsed.is_a?(Hash) && uoeng_courses_shape?(parsed["courses_enrolled"]) && uoeng_scalar_shape?(parsed)
    end

    def uoeng_courses_shape?(courses)
      courses.nil? || (courses.is_a?(Array) && courses.all?(String))
    end

    def uoeng_scalar_shape?(parsed)
      [true, false, nil].include?(parsed["student_this_semester"]) &&
        parsed.values_at("faculty", "first_name", "last_name").all? { |part| part.nil? || part.is_a?(String) }
    end

    def uoeng_http_failure(response, elapsed, card_number, space)
      TapBoxLog.log_api_http_error(
        user: self,
        http_status: response.status,
        elapsed_ms: elapsed,
        response: response,
        card_number: card_number,
        space: space
      )
      uoeng_no_answer(UpstreamError.new("uOEng answered HTTP #{response.status}"), response.status >= 500 ? :unavailable : :unknown)
    end

    def uoeng_unknown(error)
      uoeng_no_answer(error, :unknown)
    end

    def uoeng_no_answer(error, kind)
      Rails.error.report(error, handled: true, context: { user_id: id })
      kind
    end

    def detect_name_mismatch(details, card_number, space)
      uoeng_name = [details["first_name"], details["last_name"]].compact.join(" ").strip
      return if uoeng_name.blank?
      return if name.to_s.downcase.include?(uoeng_name.split(" ").first&.downcase.to_s)

      TapBoxLog.log_name_mismatch(user: self, card_number: card_number, space: space)
    end

    # The answer, or :mismatch when it carries a student number other than the
    # one on the account (the typed number is left as it is). The mismatch is
    # logged for staff.
    def checked_uoeng_answer(parsed, card_number, space)
      return parsed unless uoeng_student_number_differs?(parsed)

      TapBoxLog.log_student_id_mismatch(user: self, card_number: card_number, space: space)
      :mismatch
    end

    # uOEng sends the student number as `emplid`; `student_number` is read as a fallback.
    def uoeng_student_number_differs?(parsed)
      verified = parsed["emplid"].presence || parsed["student_number"].presence
      student_id.present? && verified.present? && !same_student_number?(verified, student_id)
    end

    # All-digit numbers are compared as numbers, so an integer answer that lost
    # a leading zero still matches; anything else is compared as text.
    def same_student_number?(verified, typed)
      verified = verified.to_s.strip
      typed = typed.to_s.strip
      return verified == typed unless [verified, typed].all?(/\A\d+\z/)

      Integer(verified, 10) == Integer(typed, 10)
    end
  end
end