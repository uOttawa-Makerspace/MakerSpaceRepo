# frozen_string_literal: true

module Api
  module V1
    # Help form for the React app (replaces the old PUT /send_email). Public or signed in.
    # Same persistence and mail path as HelpController: a Help record (which opens the GitHub
    # issue, text defanged) and MsrMailer.issue_email (signed in: to the account, bcc the MakerRepo
    # team) or MsrMailer.issue_email_to_team (anonymous: team only, reporter in Reply-To).
    # No Turnstile (the React app cannot render it): the rate limits below are the abuse
    # control. A signed-in caller's name and email always come from the account.
    # Contract: doc/api/v1/support_requests.md.
    class SupportRequestsController < BaseController
      MAX = { name: 200, email: 254, subject: 200, comments: 5000, app_version: 50 }.freeze

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
        help = Help.new(attrs.slice(:subject, :comments))
        help.defang_github_text = true
        help.name = current_user&.name || attrs[:name]
        help.email = current_user&.email || attrs[:email]

        errors = length_errors(attrs)
        help.valid?
        errors = help.errors.to_hash.merge(errors) { |_k, a, b| a | b }
        errors.delete(:base)
        return render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: errors) if errors.any?

        if help.save
          version = attrs[:app_version].presence
          text = help.comments.to_plain_text
          if current_user
            MsrMailer.issue_email(help.name, help.email, help.subject, text, nil, version).deliver_later
          else
            # Anonymous: never mail the caller-supplied address (mail relay). Team only, reporter in Reply-To.
            MsrMailer.issue_email_to_team(help.name, help.email, help.subject, text, version).deliver_later
          end
          render json: { status: "accepted" }, status: :accepted
        else
          # The GitHub issue could not be opened: nothing was saved or sent.
          render_error(:service_unavailable, "Could not submit the request, please try again later",
                       status: :service_unavailable)
        end
      end

      private

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
