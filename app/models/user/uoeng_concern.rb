# frozen_string_literal: true

# Queries uOEng via student ID or student email to figure out if a student is
# paying CEED fees or not on their tuition. User-specific module
module User::UoengConcern
  include ApplicationHelper
  extend ActiveSupport::Concern

  included do
    # Verify if user qualifies for a faculty membership.
    #
    # NOTE: The uOEng call is expensive and we don't want them to think we're
    # batch-calling. Don't call this anywhere popular (such as in views, GET
    # actions, etc.)
    #
    # Optional keyword args for tap box console logging context:
    #   card_number: the RFID card number that triggered this check
    #   space: the Space where the tap occurred
    def validate_uoeng_membership(card_number: nil, space: nil)
      faculty_tier = MembershipTier.find_by!(title_en: "Faculty membership")

      if engineering?(card_number: card_number, space: space)
        # Student is an engineer, make a membership
        memberships.active.find_or_create_by(
          membership_tier: faculty_tier,
          status: :paid,
          end_date: end_of_this_semester
        )
      else
        # NOT an engineer, revoke any faculty memberships. Students can
        # drop/change courses mid-semester.
        revoked = memberships.active.where(membership_tier_id: faculty_tier.id)
        if revoked.any?
          TapBoxLog.log_membership_revocation(
            user: self,
            revoked_count: revoked.count,
            revoked_ids: revoked.pluck(:id),
            card_number: card_number,
            space: space
          )
        end
        revoked.update_all(status: :revoked)
        Rails.logger.info "Revoked faculty membership for user id #{id}"
        nil
      end
    end

    private

    # Is user paying the CEED fee?
    def engineering?(card_number: nil, space: nil)
      # HACK: Cheat for CI tests
      return faculty == "Engineering" if Rails.env.test?

      details = uoeng_details(card_number: card_number, space: space)

      unless details
        TapBoxLog.log_no_queryable_identifier(user: self, card_number: card_number, space: space)
        return false
      end

      is_fulltime_eng = details["student_this_semester"] && details["faculty"] == "GENIE"
      enrolled_gng = details["courses_enrolled"]&.any? { |course| course.include? "GNG" }
      result = is_fulltime_eng || enrolled_gng

      unless result
        TapBoxLog.log_not_engineering(user: self, api_details: details, card_number: card_number, space: space)
      end

      detect_name_mismatch(details, card_number, space)

      result
    rescue StandardError => e
      TapBoxLog.log_engineering_check_error(user: self, exception: e, card_number: card_number, space: space)
      false
    end

    # Query and parse user details
    def uoeng_details(card_number: nil, space: nil)
      # Check if we have valid data. Either query by student ID, or uOttawa
      # email
      creds = Rails.application.credentials[Rails.env.to_sym][:uoeng]

      url =
        if student_id.present?
          "#{creds[:query_by_id]}#{student_id}"
        elsif email.ends_with? "@uottawa.ca"
          "#{creds[:query_by_email]}#{email}"
        else
          # No valid query params, early out.
          return false
        end

      api_start = Time.current
      response = Excon.get(
        url,
        headers: { Authorization: "Bearer #{creds[:student_information_key]}" },
        read_timeout: 15,
        connect_timeout: 10
      )
      elapsed = ((Time.current - api_start) * 1000).round(1)

      if elapsed > 5000
        TapBoxLog.log_slow_api(user: self, elapsed_ms: elapsed, card_number: card_number, space: space)
      end

      if response.status != 200
        TapBoxLog.log_api_http_error(
          user: self,
          http_status: response.status,
          elapsed_ms: elapsed,
          response_body: response.body,
          card_number: card_number,
          space: space
        )
      end

      parsed = JSON.parse(response.body)
      detect_student_id_mismatch(parsed, card_number, space)
      parsed
    rescue Excon::Error::Timeout => e
      elapsed = ((Time.current - api_start) * 1000).round(1)
      TapBoxLog.log_api_timeout(user: self, elapsed_ms: elapsed, exception: e, card_number: card_number, space: space)
      raise
    rescue JSON::ParserError => e
      TapBoxLog.log_api_bad_json(user: self, exception: e, response_body: response&.body, card_number: card_number, space: space)
      raise
    end

    # Detection helpers

    def detect_name_mismatch(details, card_number, space)
      uoeng_name = [details["first_name"], details["last_name"]].compact.join(" ").strip
      return if uoeng_name.blank?
      return if name.downcase.include?(uoeng_name.split(" ").first&.downcase.to_s)

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