require 'digest'

class SamlIdpController < ActionController::Base
  include SamlIdp::Controller

  protect_from_forgery

  before_action :validate_saml_request, only: [:login, :auth]

  def login
    render template: "saml/login"
  end

  def metadata
    render xml: SamlIdp.metadata.signed
  end

  def auth
    if params[:email].blank? && params[:password].blank?
      @saml_idp_fail_msg = "Incorrect email or password."
    else
      person = idp_authenticate(params[:email], params[:password])
      if person.nil?
        @saml_idp_fail_msg = "Incorrect email or password."
      else
        @saml_response = idp_make_saml_response(person)
        render :template => "saml/saml_post", :layout => false
        return
      end
    end
    render :template => "saml/login"
  end

  def logout
    idp_logout
    @saml_response = idp_make_saml_response(nil)
    render :template => "saml/saml_post", :layout => false
  end

  def idp_authenticate(email, password) # not using params intentionally
    User.authenticate(email, password)
  end

  private :idp_authenticate

  def idp_make_saml_response(found_user) # not using params intentionally
    encode_response found_user
  end

  private :idp_make_saml_response

  def idp_logout
    nil
  end

  private :idp_logout
end