# frozen_string_literal: true

require "digest"

class SamlIdpController < ApplicationController
  include SamlIdp::Controller
  include ApplicationHelper

  protect_from_forgery with: :exception

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

  # The same refusals the HTML login words (SessionsController#login_authentication),
  # as plain text for this page.
  def sign_in_error_message
    support = SessionsController::SUPPORT_EMAIL
    case @sign_in_refusal
    when :locked
      locked_user = User.username_or_email(params[:username])
      wait =
        if locked_user&.locked_until
          " or wait #{ActionController::Base.helpers.distance_of_time_in_words(locked_user.locked_until, Time.current)}"
        end
      "Your account has been locked due to too many failed login attempts. Please contact an administrator at #{support} to unlock your account#{wait}."
    when :unconfirmed
      "Please confirm your account before logging in. You can resend the confirmation email from the MakerRepo login page."
    when :inactive
      "Your account is inactive. Please contact an administrator at #{support}."
    else
      "Invalid username/password"
    end
  end
end
