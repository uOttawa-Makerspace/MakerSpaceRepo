require 'digest'

class SamlIdpController < ActionController::Base
  include SamlIdp::Controller

  unloadable unless Rails::VERSION::MAJOR >= 4
  protect_from_forgery

  if Rails::VERSION::MAJOR >= 4
    before_action :validate_saml_request, only: [:new, :create]
  else
    before_filter :validate_saml_request, only: [:new, :create]
  end

  def new
    render template: "saml/new"
  end

  def show
    render xml: SamlIdp.metadata.signed
  end

  def create
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
    render :template => "saml/new"
  end

  def logout
    idp_logout
    @saml_response = idp_make_saml_response(nil)
    render :template => "saml/saml_post", :layout => false
  end

  def idp_authenticate(email, password) # not using params intentionally
    user = User.authenticate(email, password)

    if user
      {:email_address => user.email, :id => Digest::SHA1.hexdigest(email), :username => user.username, :name => user.name}
    end
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