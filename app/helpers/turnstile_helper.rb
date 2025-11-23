# Helper to insert cloudflare turnstile captcha
module TurnstileHelper
  TURNSTILE_SITEVERIFY_ENDPOINT =
    'https://challenges.cloudflare.com/turnstile/v0/siteverify'.freeze
  private_constant :TURNSTILE_SITEVERIFY_ENDPOINT

  def creds
    Rails.application.credentials[Rails.env.to_sym][:cloudflare][:turnstile]
  end

  def turnstile_tag()
    provide(:insert_turnstile_scripts, true)
    tag.div class: 'cf-turnstile', data: { sitekey: creds[:site_key] }
  end

  def verify_turnstile
    cf_turnstile_response = params['cf-turnstile-response']
    response =
      Excon.post(
        TURNSTILE_SITEVERIFY_ENDPOINT,
        headers: {
          'Content-Type' => 'application/json'
        },
        body: {
          'secret' => creds[:secret_key],
          'response' => cf_turnstile_response,
          'remoteip' => request.ip
        }.to_json
      )

    # Cloudflare does returns a body with explanation if a check fails, but all
    # we care about is the response. Not sure if we can rely on the HTTP status
    # code, so do parse for success json value
    begin
      # Parse and return success value
      JSON.parse(response.body)['success']
    rescue StandardError => e
      Rails.logger.warn e.message
      false
    end
  end
end
