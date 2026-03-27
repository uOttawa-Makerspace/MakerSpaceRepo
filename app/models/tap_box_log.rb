class TapBoxLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  CARD_TAP         = "card_tap"
  SIGN_IN          = "sign_in"
  SIGN_OUT         = "sign_out"
  ERROR            = "error"
  WARNING          = "warning"
  INFO             = "info"
  MEMBERSHIP_CHECK = "membership_check"

  EVENT_TYPES = [CARD_TAP, SIGN_IN, SIGN_OUT, ERROR, WARNING, INFO, MEMBERSHIP_CHECK].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc).limit(500) }

  after_create_commit :broadcast_log

  # Generic Log

  def self.log!(event_type:, message:, card_number: nil, user: nil, space: nil, mac_address: nil, details: nil)
    create!(
      event_type: event_type,
      message: message,
      card_number: card_number,
      user: user,
      space: space,
      mac_address: mac_address,
      details: details
    )
  rescue => e
    Rails.logger.error("[TapBoxLog] Failed to write log: #{e.message}")
  end

  # uOEng-specific loggers

  def self.log_no_queryable_identifier(user:, card_number: nil, space: nil)
    log!(
      event_type: WARNING,
      message: "Cannot query uOEng for #{user.name} — no student ID and no @uottawa.ca email",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "no_queryable_identifier",
        student_id: user.student_id,
        email: user.email,
        suggestion: "Student may have mistyped their student number or is using a non-uOttawa email"
      }
    )
  end

  def self.log_not_engineering(user:, api_details:, card_number: nil, space: nil)
    log!(
      event_type: MEMBERSHIP_CHECK,
      message: "#{user.name} is NOT engineering — faculty: #{api_details['faculty'] || 'unknown'}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "not_engineering",
        student_this_semester: api_details["student_this_semester"],
        faculty: api_details["faculty"],
        courses_enrolled: api_details["courses_enrolled"]
      }
    )
  end

  def self.log_membership_revocation(user:, revoked_count:, revoked_ids:, card_number: nil, space: nil)
    log!(
      event_type: MEMBERSHIP_CHECK,
      message: "Revoking #{revoked_count} active faculty membership(s) for #{user.name}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "no_longer_engineering",
        revoked_membership_ids: revoked_ids
      }
    )
  end

  def self.log_name_mismatch(user:, uoeng_name:, card_number: nil, space: nil)
    log!(
      event_type: WARNING,
      message: "Name mismatch: uOEng says '#{uoeng_name}' but account is '#{user.name}'",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "name_mismatch",
        uoeng_name: uoeng_name,
        makerepo_name: user.name,
        suggestion: "Student may have linked someone else's card, or changed their name"
      }
    )
  end

  def self.log_student_id_mismatch(user:, uoeng_student_id:, card_number: nil, space: nil)
    log!(
      event_type: WARNING,
      message: "Student ID mismatch: account has '#{user.student_id}' but uOEng returned '#{uoeng_student_id}'",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "student_id_mismatch",
        makerepo_student_id: user.student_id,
        uoeng_student_id: uoeng_student_id,
        suggestion: "Student may have mistyped their student number during sign-up"
      }
    )
  end

  def self.log_slow_api(user:, elapsed_ms:, card_number: nil, space: nil)
    log!(
      event_type: WARNING,
      message: "uOEng API slow response: #{elapsed_ms}ms for #{user.name}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "slow_api_response",
        elapsed_ms: elapsed_ms,
        suggestion: "Membership check runs async so sign-in was not affected, but staff dashboard popup may have been delayed"
      }
    )
  end

  def self.log_api_http_error(user:, http_status:, elapsed_ms:, response_body: nil, card_number: nil, space: nil)
    log!(
      event_type: ERROR,
      message: "uOEng API returned HTTP #{http_status} for #{user.name}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "uoeng_http_error",
        http_status: http_status,
        elapsed_ms: elapsed_ms,
        response_body: response_body&.truncate(500)
      }
    )
  end

  def self.log_api_timeout(user:, elapsed_ms:, exception:, card_number: nil, space: nil)
    log!(
      event_type: ERROR,
      message: "uOEng API timed out after #{elapsed_ms}ms for #{user.name}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "uoeng_timeout",
        elapsed_ms: elapsed_ms,
        exception_class: exception.class.name,
        suggestion: "uOEng server may be down or overloaded"
      }
    )
  end

  def self.log_api_bad_json(user:, exception:, response_body: nil, card_number: nil, space: nil)
    log!(
      event_type: ERROR,
      message: "uOEng API returned unparseable response for #{user.name}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "uoeng_bad_json",
        response_body: response_body&.truncate(500),
        exception_message: exception.message
      }
    )
  end

  def self.log_engineering_check_error(user:, exception:, card_number: nil, space: nil)
    log!(
      event_type: ERROR,
      message: "Engineering check failed for #{user.name}: #{exception.class} — #{exception.message}",
      card_number: card_number,
      user: user,
      space: space,
      details: {
        reason: "engineering_check_exception",
        exception_class: exception.class.name,
        exception_message: exception.message,
        backtrace: exception.backtrace&.first(3)
      }
    )
    Rails.logger.fatal exception
  end

  # Housekeeping

  def self.purge_old!(days: 30)
    where("created_at < ?", days.days.ago).delete_all
  end

  private

  def broadcast_log
    Turbo::StreamsChannel.broadcast_prepend_to(
      "tap_box_console",
      target: "console-body",
      partial: "staff/tap_box_console/log_row",
      locals: { log: self, streamed: true }
    )
  end
end