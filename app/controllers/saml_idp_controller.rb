# frozen_string_literal: true

require "digest"

class SamlIdpController < ApplicationController
  include SamlIdp::Controller
  include ApplicationHelper

  protect_from_forgery with: :exception

  before_action :enforce_saml_request, only: %i[login auth]

  # Password guesses over SAML get the same budget as SessionsController#login_authentication
  # (10 per 3 minutes per IP). Only the credential submission is counted.
  rate_limit to: 10, within: 3.minutes, only: :auth, if: -> { params[:submit] == "sign_in" }, with: -> {
    @error_message = "Too many requests. Please wait a few minutes and try again."
    render template: "saml/login", status: :too_many_requests
  }

  layout false # this is technically outside the "standard" website

  def login
    @current_user = current_user if signed_in?

    render template: "saml/login"
  end

  def metadata
    render xml: SamlIdp.metadata.signed
  end

  def wiki_metadata
    render file: "public/assets/metadata.xml", content_type: "application/xml"
  end

  def auth
    @current_user =
      case params[:submit]
      when "sign_in"
        user = sign_in(params[:username], params[:password])

        @error_message = sign_in_error_message if user.nil?

        user
      when "current_user"
        current_user if signed_in?
      when "logout"
        sign_out
        nil
      else
        @error_message = "Invalid request"
        nil
      end

    if @current_user.nil?
      render template: "saml/login"
    else
      @saml_response = encode_response @current_user
      render template: "saml/saml_post"
    end
  end

  private

  # The gem's validate_saml_request only returns true/false, which a
  # before_action cannot act on, so check the verdict here and halt:
  #   400 - no request, or one that is not a parseable AuthnRequest/LogoutRequest
  #   403 - a well-formed request from an unknown issuer, an ACS host the SP is
  #         not registered for, or one whose required signature does not verify
  def enforce_saml_request
    raw = params[:SAMLRequest]
    return head :bad_request unless raw.is_a?(String) && raw.present?

    begin
      valid = validate_saml_request(raw)
      malformed = saml_request.issuer.blank? || saml_request.errors.include?(:unaccepted_request)
    rescue StandardError => e # undecodable payload, bad XML, unparseable ACS URL
      Rails.logger.info("SAML request rejected as malformed: #{e.class}")
      return head :bad_request
    end

    return if valid
    return head :bad_request if malformed

    Rails.logger.warn("SAML request refused for issuer #{saml_request.issuer.to_s.truncate(200).inspect}: #{saml_request.errors.join(',')}")
    head :forbidden
  end

  # The same refusals the HTML login words (SessionsController#login_authentication),
  # as plain text for this page.
  def sign_in_error_message
    support = SessionsController::SUPPORT_EMAIL
    case @sign_in_refusal
    when :locked
      locked_user = User.username_or_email(params[:username])
      "Your account has been locked due to too many failed login attempts. Please contact an administrator at #{support} to unlock your account#{lock_wait_suffix(locked_user)}."
    when :unconfirmed
      "Please confirm your account before logging in. You can resend the confirmation email from the MakerRepo login page."
    when :inactive
      "Your account is inactive. Please contact an administrator at #{support}."
    else
      "Invalid username/password"
    end
  end
end
