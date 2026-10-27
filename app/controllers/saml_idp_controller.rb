# frozen_string_literal: true

require "digest"

class SamlIdpController < ApplicationController
  include SamlIdp::Controller
  include ApplicationHelper

  protect_from_forgery with: :exception

  # What the gem raises for a malformed (as opposed to refused) request. Anything
  # else (SP metadata getter, DB, network) is a server failure and must surface.
  MALFORMED_REQUEST_ERRORS = [Zlib::Error, Nokogiri::XML::SyntaxError, URI::InvalidURIError].freeze

  # The wiki-server SP's metadata. No copy of it exists in the repository or its
  # history; the tracked location is checked first, the old precompile-dir path
  # (git-ignored, hand-placed) is kept so existing deploys keep working.
  WIKI_METADATA_PATHS = [
    Rails.root.join("config/saml/wiki_metadata.xml"),
    Rails.root.join("public/assets/metadata.xml")
  ].freeze

  before_action :enforce_saml_request, only: %i[login auth]

  # Password guesses over SAML draw on the SAME budget as
  # SessionsController#login_authentication (one limit, window and cache key per IP).
  # Only the credential submission is counted.
  rate_limit(**SessionsController::SIGN_IN_RATE_LIMIT, only: :auth, if: -> { params[:submit] == "sign_in" }, with: -> {
    @error_message = "Too many requests. Please wait a few minutes and try again."
    render template: "saml/login", status: :too_many_requests
  })

  layout false # this is technically outside the "standard" website

  def login
    @current_user = current_user if signed_in?

    render template: "saml/login"
  end

  def metadata
    render xml: SamlIdp::MetadataBuilder.new(metadata_configuration).signed
  end

  def wiki_metadata
    path = WIKI_METADATA_PATHS.find(&:file?)
    if path.nil?
      Rails.logger.error("SAML wiki metadata not found; looked in #{WIKI_METADATA_PATHS.join(', ')}")
      return head :not_found
    end

    render xml: path.read
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

  # Signature, SigAlg and RelayState are plain strings, and a Signature needs its SigAlg.
  def saml_binding_params_wellformed?
    values = params.values_at(:Signature, :SigAlg, :RelayState)
    values.all? { |v| v.nil? || v.is_a?(String) } && (params[:Signature].blank? || params[:SigAlg].present?)
  end

  # The Issuer on assertions. With SAML_IDP_BASE_URL set it is the same value the
  # metadata advertises as entityID (so an SP configured from the metadata accepts
  # the responses); unset, the gem's request-derived URL is kept.
  def issuer_uri
    configured_base_url ? "#{configured_base_url}/saml/auth" : super
  end

  def configured_base_url
    ENV["SAML_IDP_BASE_URL"].presence&.chomp("/")
  end

  # The IdP's public base URL: SAML_IDP_BASE_URL when set (use it behind a proxy
  # that rewrites the host), otherwise the host this request came in on.
  def saml_base_url
    configured_base_url || request.base_url
  end

  # A per-request copy of the global config with the entityID and SSO endpoints
  # filled in. The entityID is the SSO URL, which is also the Issuer the gem puts
  # on assertions (the request URL), so SPs see one consistent identity. The
  # global base_saml_location is left unset so assertion Issuers do not change.
  def metadata_configuration
    SamlIdp.config.dup.tap do |config|
      sso = "#{saml_base_url}/saml/auth"
      config.entity_id = sso
      config.single_service_post_location = sso
      config.single_service_redirect_location = sso
    end
  end

  # The gem's validate_saml_request only returns true/false, which a
  # before_action cannot act on, so check the verdict here and halt:
  #   400 - no request, or one that is not a parseable AuthnRequest/LogoutRequest
  #   403 - a well-formed request from an unknown issuer, an ACS host the SP is
  #         not registered for, or one whose required signature does not verify
  def enforce_saml_request
    raw = params[:SAMLRequest]
    return head :bad_request unless raw.is_a?(String) && raw.present?
    return head :bad_request unless saml_binding_params_wellformed?

    begin
      valid = validate_saml_request(raw)
      malformed = saml_request.issuer.blank? || saml_request.errors.include?(:unaccepted_request)
    rescue *MALFORMED_REQUEST_ERRORS => e # undecodable payload, bad XML, unparseable ACS URL
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
