class GithubIssuesService
  TOKEN_EXPIRY_BUFFER = 300

  # Send an issue and return the issue number
  def create_issue(reporter:, title:, body:)
    return {number: "111"} if Rails.env.test? || Rails.env.development?
    
    # Hardcoded lol
    repo = 'uOttawa-Makerspace/CEED-Issues'

    final_body = <<~BODY
      **Reported by:** #{reporter}
      
      ### Description
      #{body}
      
      ---
      *This issue was automatically generated from the application bug report form.*
    BODY

    client.create_issue(
      repo,
      title,
      final_body,
      { labels: %w[bug-report user-submitted] }
    )
  rescue Octokit::Error => e
    Rails.logger.error("GitHub API Error: #{e.message}")
    false
  end

  def initialize(target: nil)
    @target = target
    @token_expires = nil
    @client = nil
  end

  def client
    creds = Rails.application.credentials[Rails.env.to_sym].github.ceed_issues

    # Check if token needs renewal first
    if @token_expires.nil? ||
       Time.current.to_i >= @token_expires - TOKEN_EXPIRY_BUFFER
      
      # Clock skew, also good practice for general JWT
      now = Time.current.to_i
      jwt_payload = { iat: now - 60, exp: now + 540, iss: creds.app_id }
      # Read RSA private key from credentials
      private_key = OpenSSL::PKey::RSA.new(creds.private_key)
      # Sign JWT
      jwt = JWT.encode(jwt_payload, private_key, 'RS256')
      # Authenticate application with JWT
      app_client = Octokit::Client.new(bearer_token: jwt)
      # Get access token for organization
      access_token =
        app_client.create_app_installation_access_token(
          creds.installation_id
        ).token
      @token_expires = now + 3600
      # Authenticate as organization
      @client = Octokit::Client.new(access_token: access_token)
    end
    @client
    
  rescue Octokit::Error => e
    Rails.logger.error(e)
    raise
  end
end
