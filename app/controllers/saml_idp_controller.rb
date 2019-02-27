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
    user = User.authenticate(params[:email], params[:password])
    if user.nil?
      @saml_idp_fail_msg = "Incorrect email or password – Nom d'utilisateur ou mot de passe incorrect"
    else
      @saml_response = encode_response user
      render :template => "saml/saml_post", :layout => false
      return
    end
    render :template => "saml/login"
  end
end