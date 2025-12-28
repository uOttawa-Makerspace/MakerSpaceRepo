# frozen_string_literal: true

require "digest"

class SamlIdpController < ApplicationController
  include SamlIdp::Controller
  include ApplicationHelper

  protect_from_forgery

  before_action :validate_saml_request, only: %i[login auth]

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

        @error_message = "Invalid username/password" if user.nil?

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
      # Debug logging - remove after fixing
      Rails.logger.info "=== SAML Debug ==="
      Rails.logger.info "Issuer: #{saml_request&.issuer.inspect}"
      Rails.logger.info "ACS URL: #{saml_acs_url.inspect}"
      Rails.logger.info "User: #{@current_user.email}"
      Rails.logger.info "=================="

      @saml_response = encode_response @current_user
      render template: "saml/saml_post"
    end
  end
end