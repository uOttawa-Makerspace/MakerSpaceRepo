# Module to centralize connections to credly
module CredlyConcern
  extend ActiveSupport::Concern

  class_methods do
    # Authenticate a call to Credly
    def credly_api_call(method, endpoint: "", body: {}, url: "")
      # fill in default, because this function could be used in a loop sometimes
      url = "#{CredlyConcern.endpoint_root}#{endpoint}" if url.blank?
      body = body.blank? ? nil : body.to_json
      headers = {
        "Authorization" => "Bearer #{CredlyConcern.access_token}",
        "Accept" => "application/json",
        "Content-type" => "application/json"
      }

      # Using Excon connections throws an SSL EoF error
      # And I wasn't bothering to investigate
      case method
      when :get
        Excon.get(url, body:, headers:)
      when :post
        Excon.post(url, body:, headers:)
      when :put
        Excon.put(url, body:, headers:)
      when :delete
        Excon.delete(url, body:, headers:)
      else
        raise ArgumentError, 'Invalid HTTP verb'
      end
    end
  end

  # Get an OAuth2 token for API calls, expires in 7200 seconds
  def self.access_token
    oauth_endpoint = Rails.application.credentials[Rails.env.to_sym][:acclaim][:oauth_token_endpoint]
    application_id = Rails.application.credentials[Rails.env.to_sym][:acclaim][:oauth_application_id]
    client_secret = Rails.application.credentials[Rails.env.to_sym][:acclaim][:oauth_client_secret]

    response = Excon.post(oauth_endpoint,
                          headers: { "Content-Type" => "application/json" },
                          body: {
                            client_id: application_id,
                            client_secret: client_secret,
                            "grant_type" => 'client_credentials',
                            "scope" => "badge_templates issued_badges"
                          }.to_json)
    JSON.parse(response.body)["access_token"]
  end

  # api.credly.com/v1/organizations/<org_id>/
  def self.endpoint_root
    domain = Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]
    org_id = Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]
    "#{domain}/v1/organizations/#{org_id}/"
  end

end
