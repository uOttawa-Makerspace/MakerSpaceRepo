# require 'rails_helper'
#
# RSpec.describe SamlIdpController, type: :controller do
#
#   describe "POST /auth" do
#
#     context "auth with saml" do
#
#       it 'should not log in (wrong saml request)' do
#         post :auth, params: {SAMLRequest: "abc"}
#         expect(response).to have_http_status(403)
#       end
#
#       it 'should not log in (wrong password)' do
#         user = create(:user, :regular_user)
#         post :auth, params: {submit: "sign_in", email: user.email, password: "abc#", RelayState: "https%3A%2F%2Fwiki.makerepo.com%2Fwiki%2FSpecial%3APluggableAuthLogin", SAMLRequest: "fZLbTsMwDIZfpcp9j1ubErWVxibEpAHTVrjgBmWty6K1SYlTDm9P14IYmrSrKLY%2F%2F%2FafJMibumWzzuzlBt46QGN9NrVENiRS0mnJFEeBTPIGkJmCbWd3KxY4Hmu1MqpQNTlBLhMcEbQRShJruUjJiz8J%2FCimRUFD8ON4F5cVvYppRCfTGCpeel7khRS8qCLWE2jsyZT0jXocsYOlRMOl6UNe4NketYM490MWUjb1n4m16LcRkpuB2hvTInPdhh9AQ6ucQjXucWKX98sTa%2FY72lxJ7BrQW9DvooDHzeoP%2FhAH4Zx3aFTZ1eC0%2B3a843gGNi9wiJ5xxFr%2FmHctZCnk62XfdmMRsts8X9vrh21OsuQowQYfdHYmkLin6WR85vu%2B8XKxVrUovqwbpRtuLuseI6K0q6GUGc0lCpCmd6uu1cdcAzeQEqM7IG42Sv7%2FTNk3"}
#         expect(response).to have_http_status(403)
#       end
#
#       it 'should log in with password' do
#         user = create(:user, :regular_user)
#         post :auth, params: {submit: "sign_in", email: user.email, password: "asa32A353#", RelayState: "https%3A%2F%2Fwiki.makerepo.com%2Fwiki%2FSpecial%3APluggableAuthLogin", SAMLRequest: "fZLbTsMwDIZfpcp9j1ubErWVxibEpAHTVrjgBmWty6K1SYlTDm9P14IYmrSrKLY%2F%2F%2FafJMibumWzzuzlBt46QGN9NrVENiRS0mnJFEeBTPIGkJmCbWd3KxY4Hmu1MqpQNTlBLhMcEbQRShJruUjJiz8J%2FCimRUFD8ON4F5cVvYppRCfTGCpeel7khRS8qCLWE2jsyZT0jXocsYOlRMOl6UNe4NketYM490MWUjb1n4m16LcRkpuB2hvTInPdhh9AQ6ucQjXucWKX98sTa%2FY72lxJ7BrQW9DvooDHzeoP%2FhAH4Zx3aFTZ1eC0%2B3a843gGNi9wiJ5xxFr%2FmHctZCnk62XfdmMRsts8X9vrh21OsuQowQYfdHYmkLin6WR85vu%2B8XKxVrUovqwbpRtuLuseI6K0q6GUGc0lCpCmd6uu1cdcAzeQEqM7IG42Sv7%2FTNk3"}
#         expect(response).to have_http_status(200)
#       end
#
#       it 'should log in (already logged in)' do
#         user = create(:user, :regular_user)
#         session[:expires_at] = DateTime.tomorrow.end_of_day
#         session[:user_id] = user.id
#         post :auth, params: {submit: "current_user", authenticity_token: "WDwUEFEci+2gOE/fja/s+GY8tIYwjHbYBtfZubPTMcSngYw+3XwUNJQoq/9fPuQvQESPtRNWJW77MDI1HCd3BQ==", SAMLRequest: "fZLbTsMwDIZfpcp9j1ubErWVxibEpAHTVrjgBmWty6K1SYlTDm9P14IYmrSrKLY%2F%2F%2FafJMibumWzzuzlBt46QGN9NrVENiRS0mnJFEeBTPIGkJmCbWd3KxY4Hmu1MqpQNTlBLhMcEbQRShJruUjJiz8J%2FCimRUFD8ON4F5cVvYppRCfTGCpeel7khRS8qCLWE2jsyZT0jXocsYOlRMOl6UNe4NketYM490MWUjb1n4m16LcRkpuB2hvTInPdhh9AQ6ucQjXucWKX98sTa%2FY72lxJ7BrQW9DvooDHzeoP%2FhAH4Zx3aFTZ1eC0%2B3a843gGNi9wiJ5xxFr%2FmHctZCnk62XfdmMRsts8X9vrh21OsuQowQYfdHYmkLin6WR85vu%2B8XKxVrUovqwbpRtuLuseI6K0q6GUGc0lCpCmd6uu1cdcAzeQEqM7IG42Sv7%2FTNk3"}
#         expect(response).to have_http_status(200)
#       end
#
#     end
#
#   end
#
# end
