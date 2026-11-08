# frozen_string_literal: true

module User::UoengConcern
  extend ActiveSupport::Concern
  include ApplicationHelper

  UpstreamError = Class.new(StandardError)

  included do
    # Verify if user qualifies for a faculty membership. Returns the granted
    # membership, nil when the user is not engineering (any active faculty
    # membership is revoked), or :unknown when the upstream could not answer:
    # then the stored memberships are left exactly as they are.
    def validate_uoeng_membership(card_number: nil, space: nil)
      faculty_tier = MembershipTier.find_by!(title_en: "Faculty membership")

      case engineering?(card_number: card_number, space: space)
      when :unknown then :unknown
      when true then grant_faculty_membership(faculty_tier)
      else revoke_faculty_memberships(faculty_tier, card_number: card_number, space: space)
      end
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

    # true, false, or :unknown when the upstream gave no usable answer.
    def engineering?(card_number: nil, space: nil)
      return faculty == "Engineering" if Rails.env.test?

      details = uoeng_details(card_number: card_number, space: space)
      return :unknown if details == :unknown

      unless details
        TapBoxLog.log_no_queryable_identifier(user: self, card_number: card_number, space: space)
        return :unknown
      end

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
    # :unknown when the upstream timed out, refused, answered with a non-200
    # status or sent a body that does not have the expected shape.
    def uoeng_details(card_number: nil, space: nil)
      creds = Rails.application.credentials.dig(Rails.env.to_sym, :uoeng) || {}

      url =
        if student_id.present?
          "#{creds[:query_by_id]}#{student_id}"
        elsif email.to_s.ends_with?("@uottawa.ca")
          "#{creds[:query_by_email]}#{email}"
        else
          return false
        end

      fetch_uoeng_details(url, creds[:student_information_key], card_number, space)
    end

    def fetch_uoeng_details(url, key, card_number, space)
      api_start = Time.current
      response = Excon.get(url, headers: { Authorization: "Bearer #{key}" }, read_timeout: 15, connect_timeout: 10)
      elapsed = ((Time.current - api_start) * 1000).round(1)

      TapBoxLog.log_slow_api(user: self, elapsed_ms: elapsed, card_number: card_number, space: space) if elapsed > 5000
      return uoeng_http_failure(response, elapsed, card_number, space) if response.status != 200

      parsed = JSON.parse(response.body)
      raise JSON::ParserError, "unexpected answer shape" unless expected_uoeng_shape?(parsed)

      detect_student_id_mismatch(parsed, card_number, space)
      parsed
    rescue Excon::Error::Timeout => e
      elapsed = ((Time.current - api_start) * 1000).round(1)
      TapBoxLog.log_api_timeout(user: self, elapsed_ms: elapsed, exception: e, card_number: card_number, space: space)
      uoeng_unknown(e)
    rescue JSON::ParserError => e
      TapBoxLog.log_api_bad_json(user: self, exception: e, response_body: response&.body, card_number: card_number, space: space)
      uoeng_unknown(e)
    rescue Excon::Error => e
      TapBoxLog.log_engineering_check_error(user: self, exception: e, card_number: card_number, space: space)
      uoeng_unknown(e)
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
        response_body: response.body,
        card_number: card_number,
        space: space
      )
      uoeng_unknown(UpstreamError.new("uOEng answered HTTP #{response.status}"))
    end

    def uoeng_unknown(error)
      Rails.error.report(error, handled: true, context: { user_id: id })
      :unknown
    end

    def detect_name_mismatch(details, card_number, space)
      uoeng_name = [details["first_name"], details["last_name"]].compact.join(" ").strip
      return if uoeng_name.blank?
      return if name.to_s.downcase.include?(uoeng_name.split(" ").first&.downcase.to_s)

      TapBoxLog.log_name_mismatch(user: self, uoeng_name: uoeng_name, card_number: card_number, space: space)
    end

    def detect_student_id_mismatch(parsed, card_number, space)
      return unless student_id.present? && parsed["student_number"].present?
      return if parsed["student_number"].to_s == student_id.to_s

      TapBoxLog.log_student_id_mismatch(
        user: self,
        uoeng_student_id: parsed["student_number"],
        card_number: card_number,
        space: space
      )
    end
  end
end