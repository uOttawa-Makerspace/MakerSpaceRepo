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
        membership = memberships.active.find_or_create_by(
          membership_tier: faculty_tier,
          status: :paid,
          end_date: end_of_this_semester
        )
        Rails.logger.info "Created faculty membership for user id #{id}"
        membership
      else
        # NOT an engineer, revoke any faculty memberships. Students can
        # drop/change courses mid-semester.
        revoked = memberships
          .active
          .where(membership_tier_id: faculty_tier.id)

        if revoked.any?
          TapBoxLog.log!(
            event_type: TapBoxLog::MEMBERSHIP_CHECK,
            message: "Revoking #{revoked.count} active faculty membership(s) for #{name} — no longer engineering",
            card_number: card_number,
            user: self,
            space: space,
            details: {
              revoked_membership_ids: revoked.pluck(:id),
              reason: "not_engineering_or_no_ceed_fee"
            }
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
            suggestion: "Student may have mistyped their student number during sign-up, or is using a non-uOttawa email"
          }
        )
        return false
      end

      is_fulltime_eng = details["student_this_semester"] && details["faculty"] == "GENIE"
      enrolled_gng = details["courses_enrolled"]&.any? { |course| course.include? "GNG" }
      is_engineering = is_fulltime_eng || enrolled_gng

      # Log the determination with full detail
      TapBoxLog.log!(
        event_type: TapBoxLog::MEMBERSHIP_CHECK,
        message: is_engineering ?
          "#{name} confirmed as engineering (#{is_fulltime_eng ? 'GENIE faculty' : 'GNG course enrollment'})" :
          "#{name} is NOT engineering — faculty: #{details['faculty'] || 'unknown'}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          student_this_semester: details["student_this_semester"],
          faculty: details["faculty"],
          courses_enrolled: details["courses_enrolled"],
          is_fulltime_eng: is_fulltime_eng,
          enrolled_gng: enrolled_gng,
          result: is_engineering,
          # Surface name from uOEng for mismatch detection
          uoeng_name: [details["first_name"], details["last_name"]].compact.join(" ").presence,
          makerepo_name: name
        }
      )

      # Warn if name doesn't match (possible card swap / wrong account)
      uoeng_name = [details["first_name"], details["last_name"]].compact.join(" ").strip
      if uoeng_name.present? && !name.downcase.include?(uoeng_name.split(" ").first&.downcase.to_s)
        TapBoxLog.log!(
          event_type: TapBoxLog::WARNING,
          message: "Possible name mismatch: uOEng says '#{uoeng_name}' but MakeRepo account is '#{name}'",
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

      is_engineering
    rescue StandardError => e
      # For now return false on all errors
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng engineering check failed for #{name}: #{e.class} — #{e.message}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "engineering_check_exception",
          exception_class: e.class.name,
          exception_message: e.message,
          backtrace: e.backtrace&.first(3)
        }
      )
      Rails.logger.fatal e
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

      query_method = student_id.present? ? "student_id" : "email"

      TapBoxLog.log!(
        event_type: TapBoxLog::INFO,
        message: "Querying uOEng API by #{query_method} for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          query_method: query_method,
          query_value: query_method == "student_id" ? student_id : email
        }
      )

      api_start = Time.current
      response = Excon.get(
        url,
        headers: {
          Authorization: "Bearer #{creds[:student_information_key]}"
        },
        read_timeout: 15,
        connect_timeout: 10
      )
      api_elapsed = ((Time.current - api_start) * 1000).round(1)

      if response.status != 200
        TapBoxLog.log!(
          event_type: TapBoxLog::ERROR,
          message: "uOEng API returned HTTP #{response.status} for #{name}",
          card_number: card_number,
          user: self,
          space: space,
          details: {
            reason: "uoeng_http_error",
            http_status: response.status,
            elapsed_ms: api_elapsed,
            response_body: response.body&.truncate(500)
          }
        )
      else
        TapBoxLog.log!(
          event_type: TapBoxLog::INFO,
          message: "uOEng API responded in #{api_elapsed}ms for #{name}",
          card_number: card_number,
          user: self,
          space: space,
          details: { elapsed_ms: api_elapsed, http_status: response.status }
        )
      end

      # Warn if the API is slow (> 5 seconds)
      if api_elapsed > 5000
        TapBoxLog.log!(
          event_type: TapBoxLog::WARNING,
          message: "uOEng API slow response: #{api_elapsed}ms for #{name} — box may not have flashed green in time",
          card_number: card_number,
          user: self,
          space: space,
          details: {
            reason: "slow_api_response",
            elapsed_ms: api_elapsed,
            suggestion: "The tap box returns before this check completes, so the student was already signed in, but membership may have appeared delayed on staff dashboard"
          }
        )
      end

      parsed = JSON.parse(response.body)

      # Log if student_id came back but doesn't match what we have on file
      if student_id.present? && parsed["student_number"].present? &&
         parsed["student_number"].to_s != student_id.to_s
        TapBoxLog.log!(
          event_type: TapBoxLog::WARNING,
          message: "Student ID mismatch: MakeRepo has '#{student_id}' but uOEng returned '#{parsed['student_number']}'",
          card_number: card_number,
          user: self,
          space: space,
          details: {
            reason: "student_id_mismatch",
            makerepo_student_id: student_id,
            uoeng_student_id: parsed["student_number"],
            suggestion: "Student may have mistyped their student number during account creation"
          }
        )
      end

      parsed
    rescue Excon::Error::Timeout => e
      api_elapsed = ((Time.current - api_start) * 1000).round(1)
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng API timed out after #{api_elapsed}ms for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "uoeng_timeout",
          elapsed_ms: api_elapsed,
          exception_class: e.class.name,
          suggestion: "uOEng server may be down or overloaded. Student sign-in still succeeded but membership was not verified."
        }
      )
      raise
    rescue JSON::ParserError => e
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "uOEng API returned unparseable response for #{name}",
        card_number: card_number,
        user: self,
        space: space,
        details: {
          reason: "uoeng_bad_json",
          response_body: response&.body&.truncate(500),
          exception_message: e.message
        }
      )
      raise
    end
  end
end