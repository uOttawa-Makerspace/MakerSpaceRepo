# frozen_string_literal: true

module Api
  module V1
    # Help form for the React app (replaces the old PUT /send_email). Public or signed in.
    # Same path as HelpController: the request saves a Help record and queues HelpFilingJob, which
    # mails MsrMailer.issue_email_copy_to_team plus issue_email (signed in: one mail to the MakerRepo
    # team, one to the account) or MsrMailer.issue_email_to_team (anonymous: team only, reporter in
    # Reply-To) and opens the GitHub issue (text defanged). It answers 202 once the record is saved,
    # also when the job cannot be queued (Help#queue_filing reports it and the sweep queues it again).
    # No Turnstile (the React app cannot render it): the rate limits below are the
    # protection. A signed-in caller's name and email always come from the account.
    # Contract: doc/api/v1/support_requests.md.
    class SupportRequestsController < BaseController
      skip_authorization only: :create, reason: "Public by contract: anyone may send a support request (rate limited)"

      # Raw lengths of the posted values (the model counts comments as plain text).
      MAX = Help::MAX_LENGTH.merge(subject: 200, comments: 5000, app_version: 50).freeze

      rate_limit to: 5, within: 1.minute, only: :create, scope: "api-support", name: "ip-minute",
                 by: -> { request.remote_ip }, with: :rate_limited
      rate_limit to: 20, within: 1.hour, only: :create, scope: "api-support", name: "ip-hour",
                 by: -> { request.remote_ip }, with: :rate_limited
      rate_limit to: 5, within: 1.minute, only: :create, scope: "api-support", name: "user-minute",
                 by: -> { current_user ? "user:#{current_user.id}" : "anon:#{request.remote_ip}" }, with: :rate_limited
      rate_limit to: 20, within: 1.hour, only: :create, scope: "api-support", name: "user-hour",
                 by: -> { current_user ? "user:#{current_user.id}" : "anon:#{request.remote_ip}" }, with: :rate_limited

      def create
        attrs = support_params
        fields = attrs.slice(:name, :email, :subject, :comments).merge(app_version: attrs[:app_version].presence)
        help = Help.compose(fields, user: current_user, source: Help::APP)
        errors = request_errors(help, attrs)
        return render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: errors) if errors.any?

        help.submit
        render json: { status: "accepted" }, status: :accepted
      end

      private

      def request_errors(help, attrs)
        help.valid?
        help.errors.to_hash.merge(length_errors(attrs)) { |_k, a, b| a | b }
      end

      # Unknown fields are ignored. Non-string values are rejected as blank/invalid by the checks.
      def support_params
        raw = params.permit(*MAX.keys).to_h.symbolize_keys
        MAX.each_key { |k| raw[k] = raw[k].to_s.strip if raw.key?(k) }
        raw
      end

      def length_errors(attrs)
        MAX.each_with_object({}) do |(field, max), acc|
          acc[field] = ["is too long (maximum is #{max} characters)"] if attrs[field].to_s.length > max
        end
      end
    end
  end
end
