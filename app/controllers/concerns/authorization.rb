# frozen_string_literal: true

# Makes a controller prove that every action checked who may run it.
#
# A gate (a before_action that lets the request through) or an action calls
# `authorized!(reason)` once the check passed. A controller that turns the guard on with
# `require_authorization` then verifies, after each action, that a check was recorded or that the
# action was opted out with `skip_authorization only: ..., reason: "..."`. A request a gate refused
# never reaches the verification (the callback chain stops at the refusal).
#
# Rules about a record are positive predicates on the model that take the user, for example
# `rental.editable_by?(user)`. `authorize!(rental, :editable_by?)` calls it with the current user,
# records the check when it holds and refuses the request when it does not.
#
# A missed check raises in development and test. In production it is reported through
# Rails.error and the request carries on.
module Authorization
  extend ActiveSupport::Concern

  class NotChecked < StandardError; end

  included do
    class_attribute :authorization_required, default: false
    class_attribute :authorization_skips, default: {}
  end

  class_methods do
    # Turns the guard on for this controller and its subclasses.
    def require_authorization
      return if authorization_required

      self.authorization_required = true
      after_action :verify_authorized
    end

    # Declares actions that need no check, and why.
    def skip_authorization(only:, reason:)
      raise ArgumentError, "skip_authorization needs a reason" if reason.to_s.strip.empty?

      skips = Array(only).to_h { |action| [action.to_s, reason] }
      self.authorization_skips = authorization_skips.merge(skips)
    end
  end

  private

  # Records that this request passed an authorization check.
  def authorized!(reason)
    @authorization_reason = reason
  end

  # Checks `record.public_send(predicate, current_user)`. The check is recorded either way; a
  # request that fails it is refused through `authorization_denied`.
  def authorize!(record, predicate)
    allowed = record.public_send(predicate, current_user)
    authorized!(predicate)
    authorization_denied unless allowed
  end

  # How a refused request is answered; a controller area overrides it to refuse its own way.
  def authorization_denied
    head :forbidden
  end

  def authorization_checked?
    @authorization_reason.present? || authorization_skips.key?(action_name)
  end

  def verify_authorized
    return if authorization_checked?

    error = NotChecked.new(
      "#{controller_path}##{action_name} ran without an authorization check. Call authorized! " \
      "from its gate, use authorize!(record, :predicate), or skip_authorization only: :#{action_name}, reason: ..."
    )
    raise error if Rails.env.local?

    Rails.error.report(error, handled: true, severity: :error,
                              context: { controller: controller_path, action: action_name })
  end
end
