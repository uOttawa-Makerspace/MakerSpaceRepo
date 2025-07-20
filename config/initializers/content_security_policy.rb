# # Be sure to restart your server when you modify this file.

# # Define an application-wide content security policy
# # For further information see the following documentation
# # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data, "https://fonts.gstatic.com"
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https

#     policy.script_src :self, :https, "https://www.google.com", "https://www.recaptcha.net", "https://www.gstatic.com", 
# "https://unpkg.com", "'unsafe-inline'", "'unsafe-eval'", "http://localhost:3036"
#     policy.frame_src :self, "https://www.youtube.com", "https://www.google.com", "https://www.recaptcha.net", "https://www.calendar.google.com"

#     policy.connect_src :self, :https, "ws://localhost:3036", "http://localhost:3036", "https://www.google.com", "https://www.recaptcha.net"


#     policy.style_src :self, :https, "'unsafe-inline'", "https://fonts.googleapis.com"
#   end

#   # Generate session nonces for permitted importmap and inline scripts
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w[script-src]

#   # Report CSP violations to a specified URI. See:
#   # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
#   # config.content_security_policy_report_only = true
# end