# frozen_string_literal: true

# Queries uOEng via student ID or student email to figure out if a student is
# paying CEED fees or not on their tuition. User-specific module
module User::UoengConcern
  include ApplicationHelper # end_of_this_semeseter
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
        log_membership_revocation(revoked, card_number, space) if revoked.any?
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
        log_no_queryable_identifier(card_number, space)
        return false
      end

      is_fulltime_eng = details["student_this_semester"] && details["faculty"] == "GENIE"
      enrolled_gng = details["courses_enrolled"]&.any? { |course| course.include? "GNG" }
      result = is_fulltime_eng || enrolled_gng

      log_not_engineering(details, card_number, space) unless result
      detect_name_mismatch(details, card_number, space)

      result
    rescue StandardError => e
      log_engineering_check_error(e, card_number, space)
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

      log_slow_api(elapsed, card_number, space) if elapsed > 5000
      log_api_http_error(response, elapsed, card_number, space) if response.status != 200

      parsed = JSON.parse(response.body)
      detect_student_id_mismatch(parsed, card_number, space)
      parsed
    rescue Excon::Error::Timeout => e
      log_api_timeout(api_start, e, card_number, space)
      raise
    rescue JSON::ParserError => e
      log_api_bad_json(response, e, card_number, space)
      raise
    end

    # ---- Tap box console logging helpers ----

    def log_no_queryable_identifier(card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::WARNING,
        message: "Cannot query uOEng for #{name} — no student ID and no @uottawa.ca email",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "no_queryable_identifier",
          student_id: student_id,
          email: email,
          suggestion: "Student may have mistyped their student number or is using a non-uOttawa email"
        }
      )
    end

    def log_not_engineering(details, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::MEMBERSHIP_CHECK,
        message: "#{name} is NOT engineering — faculty: #{details['faculty'] || 'unknown'}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "not_engineering",
          student_this_semester: details["student_this_semester"],
          faculty: details["faculty"],
          courses_enrolled: details["courses_enrolled"]
        }
      )
    end

    def log_membership_revocation(revoked, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::MEMBERSHIP_CHECK,
        message: "Revoking #{revoked.count} active faculty membership(s) for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "no_longer_engineering",
          revoked_membership_ids: revoked.pluck(:id)
        }
      )
    end

    # Warn if name doesn't match (possible card swap / wrong account)
    def detect_name_mismatch(details, card_number, space)
      uoeng_name = [details["first_name"], details["last_name"]].compact.join(" ").strip
      return if uoeng_name.blank?
      return if name.downcase.include?(uoeng_name.split(" ").first&.downcase.to_s)

      TapBoxLog.log!(
        event_type: TapBoxLog::WARNING,
        message: "Name mismatch: uOEng says '#{uoeng_name}' but account is '#{name}'",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "name_mismatch",
          uoeng_name: uoeng_name,
          makerepo_name: name,
          suggestion: "Student may have linked someone else's card, or changed their name"
        }
      )
    end

    def detect_student_id_mismatch(parsed, card_number, space)
      return unless student_id.present? && parsed["student_number"].present?
      return if parsed["student_number"].to_s == student_id.to_s

      TapBoxLog.log!(
        event_type: TapBoxLog::WARNING,
        message: "Student ID mismatch: account has '#{student_id}' but uOEng returned '#{parsed['student_number']}'",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "student_id_mismatch",
          makerepo_student_id: student_id,
          uoeng_student_id: parsed["student_number"],
          suggestion: "Student may have mistyped their student number during sign-up"
        }
      )
    end

    def log_slow_api(elapsed, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::WARNING,
        message: "uOEng API slow response: #{elapsed}ms for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "slow_api_response",
          elapsed_ms: elapsed,
          suggestion: "Membership check runs async so sign-in was not affected, but staff dashboard popup may have been delayed"
        }
      )
    end

    def log_api_http_error(response, elapsed, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng API returned HTTP #{response.status} for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "uoeng_http_error",
          http_status: response.status,
          elapsed_ms: elapsed,
          response_body: response.body&.truncate(500)
        }
      )
    end

    def log_api_timeout(api_start, error, card_number, space)
      elapsed = ((Time.current - api_start) * 1000).round(1)
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng API timed out after #{elapsed}ms for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "uoeng_timeout",
          elapsed_ms: elapsed,
          exception_class: error.class.name,
          suggestion: "uOEng server may be down or overloaded"
        }
      )
    end

    def log_api_bad_json(response, error, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng API returned unparseable response for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "uoeng_bad_json",
          response_body: response&.body&.truncate(500),
          exception_message: error.message
        }
      )
    end

    def log_engineering_check_error(error, card_number, space)
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "Engineering check failed for #{name}: #{error.class} — #{error.message}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "engineering_check_exception",
          exception_class: error.class.name,
          exception_message: error.message,
          backtrace: error.backtrace&.first(3)
        }
      )
      Rails.logger.fatal error
    end
  end
end