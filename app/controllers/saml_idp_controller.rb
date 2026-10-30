# frozen_string_literal: true

require "digest"

class SamlIdpController < ApplicationController
  include SamlIdp::Controller
  include ApplicationHelper

  # Re-declared so this controller has no legacy JSON exemption
  # (ApplicationController#legacy_json_request?): SAML is form posts only.
  protect_from_forgery with: :exception

  # What the gem raises for a malformed (as opposed to refused) request. Anything
  # else (SP metadata getter, DB, network) is a server failure and must surface.
  MALFORMED_REQUEST_ERRORS = SamlSignatureGuard::PARSE_ERRORS

  # The wiki-server SP's metadata. No copy of it exists in the repository or its
  # history, so placing it at config/saml/wiki_metadata.xml is a deploy step. The
  # old precompile-dir path (git-ignored, hand-placed) is still read as a fallback
  # so existing deploys keep working.
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

  # The one verdict every caller of the gem's validation sees (validate_saml_request,
  # enforce_saml_request, any later direct call): the request must be valid AND the
  # gem must have recorded no error. The gem's valid_external_signature? returns a
  # truthy errors array when the SP certificate cannot be parsed, which `valid?`
  # alone would accept.
  def valid_saml_request?
    saml_request.valid? && saml_request.errors.empty?
  end

  # Signature, SigAlg and RelayState are plain strings; a Signature present
  # needs its SigAlg. A present-but-blank Signature/SigAlg is refused too: the gem
  # only runs its signature checks on a nil (embedded) or present (external)
  # Signature, so "Signature=" would skip both.
  def saml_binding_params_wellformed?
    return false unless params.values_at(:Signature, :SigAlg, :RelayState).all? { |v| v.nil? || v.is_a?(String) }

    %i[Signature SigAlg].none? { |key| params.key?(key) && params[key].blank? } &&
      (params[:Signature].blank? || params[:SigAlg].present?)
  end

  # The Issuer on assertions. With SAML_IDP_BASE_URL set it is the same value the
  # metadata advertises as entityID (so an SP configured from the metadata accepts
  # the responses); unset, the gem's request-derived URL is kept.
  def issuer_uri
    configured_base_url ? saml_entity_id : super
  end

  def configured_base_url
    ENV["SAML_IDP_BASE_URL"].presence&.chomp("/")
  end

  # The IdP's identity: the SSO endpoint URL. It is the metadata entityID and, via
  # issuer_uri, the Issuer on assertions.
  def saml_entity_id
    # The configured base URL already holds any mount prefix, so add the route path
    # without SCRIPT_NAME; the request-derived base never includes it, so keep it there.
    configured_base_url ? "#{configured_base_url}#{saml_auth_path(script_name: '')}" : "#{request.base_url}#{saml_auth_path}"
  end

  # A per-request copy of the global config with the entityID and SSO endpoints
  # filled in (the global config is not touched, see the attribute copy below).
  # base_saml_location stays unset on purpose: the gem would then use it as the
  # Issuer of every assertion, and the Issuer is issuer_uri's decision.
  def metadata_configuration
    SamlIdp.config.dup.tap do |config|
      # dup is shallow and the metadata builder writes :friendly_name into each
      # attribute hash, so give this copy its own hashes.
      config.attributes = config.attributes.transform_values(&:dup)
      config.entity_id = saml_entity_id
      config.single_service_post_location = saml_entity_id
      config.single_service_redirect_location = saml_entity_id
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
      decode_request(raw, params[:Signature], params[:SigAlg], params[:RelayState])
      return head :bad_request if saml_request.doctype?

      valid = valid_saml_request?
      malformed = saml_request.issuer.blank? || saml_request.errors.include?(:unaccepted_request)
    rescue *MALFORMED_REQUEST_ERRORS => e # undecodable payload, bad XML, unparseable ACS URL
      Rails.logger.info("SAML request rejected as malformed: #{e.class}")
      return head :bad_request
    rescue SamlIdp::XMLSecurity::SignedDocument::ValidationError => e # digest/fingerprint mismatch: a refusal
      Rails.logger.warn("SAML request refused: signature invalid (#{e.message.to_s.truncate(100)})")
      return head :forbidden
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
