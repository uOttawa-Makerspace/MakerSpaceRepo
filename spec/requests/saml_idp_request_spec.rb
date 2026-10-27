# frozen_string_literal: true

require "rails_helper"
require "zlib"

# Chunk 18: SamlIdpController (the SAML identity provider used by the wiki,
# Wiki.js, rooms and print). Config shape (service providers, name ids,
# attributes) is pinned in spec/config/saml_config_spec.rb; this spec pins the
# HTTP behavior: metadata, the login page (GET), the auth POST (sign in with
# credentials / use the current session / log out) and the signed response.
#
# Gate facts (verified in the controller, not assumed):
#  * SamlIdpController < ApplicationController (NOT SessionsController): no
#    session_expiry/activity hooks.
#  * `enforce_saml_request` halts on the gem's validity verdict (D-R13): 400
#    for a missing/garbage request, 403 for an unknown issuer / foreign ACS.
#  * `protect_from_forgery with: :exception` is declared here, unlike the
#    app-wide (ineffective, D-B26) declaration, so CSRF is enforced for
#    POST /saml/auth when forgery protection is enabled.
RSpec.describe "SAML IdP", type: :request do
  include Chunk18Helpers

  WIKIJS_ACS = "https://wikijs.makerepo.com/login/258365f7-0b23-403c-817a-5d1ca2be771f/callback"

  # A deflated + base64 AuthnRequest, as an SP's HTTP-Redirect binding sends it.
  def c18_authn_request(issuer: "wikijs.makerepo.com", acs: WIKIJS_ACS, id: "_req1")
    xml = %(<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ) +
          %(xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="#{id}" Version="2.0" ) +
          %(IssueInstant="2026-03-10T15:00:00Z" AssertionConsumerServiceURL="#{acs}">) +
          %(<saml:Issuer>#{issuer}</saml:Issuer></samlp:AuthnRequest>)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflated = deflater.deflate(xml, Zlib::FINISH)
    deflater.close
    Base64.strict_encode64(deflated)
  end

  def c18_form_action
    Nokogiri::HTML(response.body).at_css("form")&.[]("action")
  end

  # Decodes the SAMLResponse hidden field of the saml_post page.
  def c18_saml_response_xml
    encoded = Nokogiri::HTML(response.body).at_css("input#SAMLResponse")&.[]("value")
    encoded && Base64.decode64(encoded)
  end

  def c18_saml_attributes(xml)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    doc.xpath("//AttributeStatement/Attribute").to_h do |attr|
      [attr["Name"], attr.xpath("AttributeValue").map(&:text)]
    end
  end

  let(:password) { "asa32A353#" }

  describe "GET /saml/metadata" do
    it "is public and serves the signed IdP EntityDescriptor as application/xml" do
      get "/saml/metadata"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      doc = Nokogiri::XML(response.body)
      doc.remove_namespaces!
      expect(doc.root.name).to eq("EntityDescriptor")
      expect(doc.at_xpath("//Signature/SignedInfo/SignatureMethod")["Algorithm"]).to include("rsa-sha1")
      expect(doc.at_xpath("//IDPSSODescriptor/KeyDescriptor//X509Certificate").text.strip)
        .to eq(File.read(Rails.root.join("certs/saml.crt")).gsub(/-----(BEGIN|END) CERTIFICATE-----|\s/, ""))
      expect(doc.xpath("//IDPSSODescriptor/NameIDFormat").map(&:text)).to include(
        "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
        "urn:oasis:names:tc:SAML:2.0:nameid-format:transient",
        "urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress"
      )
      expect(doc.xpath("//IDPSSODescriptor/Attribute/@FriendlyName").map(&:value)).to include("groups", "is_admin", "role")
    end

    it "advertises the entityID, the SSO endpoints and named attributes (D-R16)" do
      get "/saml/metadata", headers: { "Host" => "idp.example.test" }
      doc = Nokogiri::XML(response.body)
      doc.remove_namespaces!
      expect(doc.root["entityID"]).to eq("http://idp.example.test/saml/auth")
      sso = doc.xpath("//IDPSSODescriptor/SingleSignOnService")
      expect(sso.map { |n| n["Location"] }.uniq).to eq(["http://idp.example.test/saml/auth"])
      expect(sso.map { |n| n["Binding"] }).to contain_exactly(
        "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST", "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
      )
      attrs = doc.xpath("//IDPSSODescriptor/Attribute")
      expect(attrs).not_to be_empty
      expect(attrs.map { |a| a["Name"] }).to all(be_present)
      expect(attrs.map { |a| a["Name"] }).to eq(attrs.map { |a| a["FriendlyName"] })
    end

    it "prefers SAML_IDP_BASE_URL over the request host" do
      stub_const("ENV", ENV.to_h.merge("SAML_IDP_BASE_URL" => "https://makerepo.com/"))
      get "/saml/metadata"
      expect(Nokogiri::XML(response.body).root["entityID"]).to eq("https://makerepo.com/saml/auth")
    end

    it "keeps the assertion Issuer the request URL (unchanged by the metadata configuration)" do
      c18_sign_in(:regular)
      post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
      doc = Nokogiri::XML(c18_saml_response_xml)
      doc.remove_namespaces!
      expect(doc.at_xpath("//Assertion/Issuer").text).to eq("http://www.example.com/saml/auth")
    end
  end

  describe "GET /saml/wiki_metadata" do
    let(:file) { Rails.root.join("public/assets/metadata.xml") }

    def with_metadata_file(content)
      made_dir = !file.dirname.exist?
      FileUtils.mkdir_p(file.dirname)
      backup = file.exist? ? file.read : nil
      content ? file.write(content) : FileUtils.rm_f(file)
      yield
    ensure
      backup ? file.write(backup) : FileUtils.rm_f(file)
      FileUtils.rmdir(file.dirname) if made_dir && file.dirname.empty?
    end

    it "serves public/assets/metadata.xml as application/xml when the file exists" do
      with_metadata_file("<EntityDescriptor entityID=\"wiki-server\"/>") do
        get "/saml/wiki_metadata"
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/xml")
        expect(response.body).to eq("<EntityDescriptor entityID=\"wiki-server\"/>")
      end
    end

    it "is a 500 when the file is missing (it lives in public/assets, which is gitignored)" do
      # WART(D-R17): the wiki SP metadata is read from the gitignored public/assets directory (precompile output), so a fresh checkout/deploy without that hand-placed file answers 500 at the URL the SP config points to
      with_metadata_file(nil) do
        get "/saml/wiki_metadata"
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe "GET /saml/auth (login page)" do
    it "shows the sign-in form to a guest and keeps the SAMLRequest in the form action" do
      request_param = c18_authn_request
      get "/saml/auth", params: { SAMLRequest: request_param, RelayState: "rs1" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="username"', 'name="password"', 'value="sign_in"')
      expect(response.body).not_to include('value="current_user"')
      expect(c18_form_action).to start_with("/saml/auth?")
      expect(Rack::Utils.parse_query(URI(c18_form_action).query)["SAMLRequest"]).to eq(request_param)
    end

    it "shows 'use this account' / 'use another account' to a signed-in user" do
      user = c18_sign_in(:regular)
      get "/saml/auth", params: { SAMLRequest: c18_authn_request }
      expect(response.body).to include('value="current_user"', 'value="logout"', user.username, ERB::Util.html_escape(user.name))
    end

    it "answers 400 for a missing or garbage SAMLRequest (D-R13)" do
      get "/saml/auth"
      expect(response).to have_http_status(:bad_request)
      get "/saml/auth", params: { SAMLRequest: "abc" }
      expect(response).to have_http_status(:bad_request)
      get "/saml/auth", params: { SAMLRequest: ["x"] }
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 403 for an unknown issuer and for an ACS host the SP is not registered for (D-R13)" do
      get "/saml/auth", params: { SAMLRequest: c18_authn_request(issuer: "evil.example.com", acs: "https://evil.example.com/acs") }
      expect(response).to have_http_status(:forbidden)
      get "/saml/auth", params: { SAMLRequest: c18_authn_request(issuer: "rooms.makerepo.com", acs: "https://evil.example.com/steal") }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /saml/auth" do
    let!(:user) { create(:user, :regular_user, password: BCrypt::Password.create(password)) }

    def post_auth(extra = {})
      post "/saml/auth", params: { SAMLRequest: c18_authn_request, RelayState: "rs1" }.merge(extra)
    end

    context "submit=sign_in" do
      it "with valid credentials answers the auto-submitting form to the SP's ACS URL carrying a signed SAMLResponse and the RelayState" do
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(response).to have_http_status(:ok)
        expect(c18_form_action).to eq(WIKIJS_ACS)
        expect(response.body).to include('name="RelayState"', 'value="rs1"')
        expect(session[:user_id]).to eq(user.id) # the app session is also established

        xml = c18_saml_response_xml
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        expect(doc.root.name).to eq("Response")
        expect(doc.root["Destination"]).to eq(WIKIJS_ACS)
        expect(doc.root["InResponseTo"]).to eq("_req1")
        expect(doc.at_xpath("//Assertion/Signature")).to be_present
        expect(doc.at_xpath("//Assertion/Conditions/AudienceRestriction/Audience").text).to eq("wikijs.makerepo.com")
        expect(doc.at_xpath("//Assertion/Subject/NameID").text).to eq(user.id.to_s) # first name id format: persistent
        expect(doc.at_xpath("//StatusCode")["Value"]).to end_with(":Success")
      end

      it "carries the attribute statement for the signed-in user (email, username, role, groups)" do
        post_auth(submit: "sign_in", username: user.username, password: password)
        attrs = c18_saml_attributes(c18_saml_response_xml)
        expect(attrs["email_address"]).to eq([user.email])
        expect(attrs["username"]).to eq([user.username])
        expect(attrs["role"]).to eq([user.role])
        expect(attrs["is_admin"]).to eq(["false"])
        expect(attrs["groups"]).to be_blank
      end

      it "maps an admin to the Wiki.js 'Administrators' group" do
        admin = create(:user, :admin, password: BCrypt::Password.create(password))
        post_auth(submit: "sign_in", username: admin.email, password: password)
        attrs = c18_saml_attributes(c18_saml_response_xml)
        expect(attrs["groups"]).to eq(["Administrators"])
        expect(attrs["is_admin"]).to eq(["true"])
      end

      it "re-renders the login page with 'Invalid username/password' (200, no assertion) on a wrong password" do
        post_auth(submit: "sign_in", username: user.username, password: "wrong")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Invalid username/password")
        expect(c18_saml_response_xml).to be_nil
        expect(session[:user_id]).to be_nil
        expect(user.reload.auth_attempts).to eq(1)
      end

      it "treats an unknown user the same way" do
        post_auth(submit: "sign_in", username: "nobody-here", password: password)
        expect(response.body).to include("Invalid username/password")
        expect(c18_saml_response_xml).to be_nil
      end

      it "refuses a LOCKED account even with the right password" do
        # FIXED(D-R14): sign_in checks the lock for every login path
        user.update!(locked: true, locked_until: 1.hour.from_now)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(c18_saml_response_xml).to be_nil
        expect(response.body).to include("Your account has been locked due to too many failed login attempts")
        expect(response.body).to include("or wait")
        expect(session[:user_id]).to be_nil
      end

      it "words an admin lock (99 years) as locked, without a 99-year wait" do
        user.update!(locked: true, locked_until: 99.years.from_now)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(response.body).to include("Your account has been locked")
        expect(response.body).not_to include("or wait")
      end

      it "words an admin lock without an end as locked, without a wait time" do
        user.update!(locked: true, locked_until: nil)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(response.body).to include("Your account has been locked")
        expect(response.body).not_to include("or wait")
      end

      it "stops evaluating guesses once the account is locked: attempts stop counting and the lock is not rewritten" do
        # FIXED(D-R14)
        (User::MAX_AUTH_ATTEMPTS + 2).times { post_auth(submit: "sign_in", username: user.username, password: "bad") }
        user.reload
        expect(user).to be_locked
        expect(user.auth_attempts).to eq(User::MAX_AUTH_ATTEMPTS)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(c18_saml_response_xml).to be_nil
      end

      it "a wrong password on an ADMIN-locked account neither shortens the lock nor revives old tokens" do
        old_token = user.token
        admin_until = 99.years.from_now
        user.update!(locked: true, locked_until: admin_until, auth_attempts: 5, token_version: user.token_version + 1)
        3.times { post_auth(submit: "sign_in", username: user.username, password: "bad") }
        user.reload
        expect(user.locked_until).to be_within(1.second).of(admin_until)
        expect(user.locked).to be(true)
        expect(User.find(user.id).token_version).to eq(1)
        expect(JwtAuthenticator.user_for("Bearer #{old_token}")).to be_nil
      end

      it "refuses an UNCONFIRMED account like the HTML login does" do
        # FIXED(D-R15)
        user.update!(confirmed: false)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(c18_saml_response_xml).to be_nil
        expect(response.body).to include("Please confirm your account before logging in")
        expect(session[:user_id]).to be_nil
      end

      it "refuses an INACTIVE account" do
        user.update!(active: false)
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(c18_saml_response_xml).to be_nil
        expect(response.body).to include("Your account is inactive.")
      end
    end

    # test env uses :null_store (never counts), so back the limiter's store with a counter
    context "rate limit (D-R14)" do
      let(:counts) { Hash.new(0) }

      before { allow(SamlIdpController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 } }

      it "allows 10 password submissions, then refuses even the correct password with 429 and no assertion" do
        10.times do
          post_auth(submit: "sign_in", username: user.username, password: "wrong")
          expect(response).to have_http_status(:ok)
        end
        post_auth(submit: "sign_in", username: user.username, password: password)
        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include("Too many requests")
        expect(c18_saml_response_xml).to be_nil
      end

      it "does not count current_user / logout submissions" do
        c18_sign_in(:regular)
        12.times { post_auth(submit: "current_user") }
        expect(response).to have_http_status(:ok)
        expect(c18_saml_response_xml).to be_present
      end
    end

    context "submit=current_user" do
      it "signed in: issues a signed assertion for the session user" do
        signed_in = c18_sign_in(:staff)
        post_auth(submit: "current_user")
        expect(response).to have_http_status(:ok)
        expect(c18_form_action).to eq(WIKIJS_ACS)
        doc = Nokogiri::XML(c18_saml_response_xml)
        doc.remove_namespaces!
        expect(doc.at_xpath("//Assertion/Subject/NameID").text).to eq(signed_in.id.to_s)
        expect(c18_saml_attributes(c18_saml_response_xml)["groups"]).to eq(["Staff Readonly"])
      end

      it "guest: no assertion; the login page is shown again without an error message" do
        post_auth(submit: "current_user")
        expect(response).to have_http_status(:ok)
        expect(c18_saml_response_xml).to be_nil
        expect(response.body).to include('value="sign_in"')
        expect(response.body).not_to include("alert-danger")
      end
    end

    context "submit=logout" do
      it "signs the app session out and shows the login form" do
        c18_sign_in(:regular)
        post_auth(submit: "logout")
        expect(response).to have_http_status(:ok)
        expect(c18_saml_response_xml).to be_nil
        expect(session[:user_id]).to be_nil
        expect(response.body).to include('value="sign_in"')
      end
    end

    it "answers 'Invalid request' for a missing or unknown submit value, even when signed in" do
      c18_sign_in(:regular)
      post_auth
      expect(response.body).to include("Invalid request")
      expect(c18_saml_response_xml).to be_nil
      post_auth(submit: "become_admin")
      expect(response.body).to include("Invalid request")
    end

    it "answers 400 (not a 500) for a missing or garbage SAMLRequest, even signed in (D-R18)" do
      c18_sign_in(:regular)
      post "/saml/auth", params: { submit: "current_user" }
      expect(response).to have_http_status(:bad_request)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: "abc" }
      expect(response).to have_http_status(:bad_request)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: Base64.strict_encode64("<not-xml") }
      expect(response).to have_http_status(:bad_request)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: ["x"] }
      expect(response).to have_http_status(:bad_request)
    end

    context "SECURITY: SAML request validation gates issuance (D-R13)" do
      it "refuses an UNKNOWN issuer with 403 and issues no assertion" do
        c18_sign_in(:regular)
        evil = c18_authn_request(issuer: "evil.example.com", acs: "https://evil.example.com/acs")
        post "/saml/auth", params: { SAMLRequest: evil, submit: "current_user" }
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include("evil.example.com")
      end

      it "refuses a registered SP (rooms) paired with a foreign ACS host" do
        c18_sign_in(:regular)
        spoofed = c18_authn_request(issuer: "rooms.makerepo.com", acs: "https://evil.example.com/steal")
        post "/saml/auth", params: { SAMLRequest: spoofed, submit: "current_user" }
        expect(response).to have_http_status(:forbidden)
        expect(c18_saml_response_xml).to be_nil
      end

      it "still issues to a registered SP whose ACS host is allowed" do
        c18_sign_in(:regular)
        ok = c18_authn_request(issuer: "rooms.makerepo.com", acs: "https://rooms.makerepo.com/users/auth/saml/callback")
        post "/saml/auth", params: { SAMLRequest: ok, submit: "current_user" }
        expect(response).to have_http_status(:ok)
        expect(c18_form_action).to eq("https://rooms.makerepo.com/users/auth/saml/callback")
        doc = Nokogiri::XML(c18_saml_response_xml)
        doc.remove_namespaces!
        expect(doc.at_xpath("//Assertion/Conditions/AudienceRestriction/Audience").text).to eq("rooms.makerepo.com")
      end

      it "a registered SP WITH a pinned acs_url (wikijs) always gets its configured ACS, whatever the request says" do
        c18_sign_in(:regular)
        spoofed = c18_authn_request(issuer: "wikijs.makerepo.com", acs: "https://evil.example.com/steal")
        post "/saml/auth", params: { SAMLRequest: spoofed, submit: "current_user" }
        expect(c18_form_action).to eq(WIKIJS_ACS)
      end

      it "refuses with 403 when the SP config requires a signed request and the request is not signed" do
        original = SamlIdp.config.service_provider.finder
        SamlIdp.config.service_provider.finder = lambda do |id|
          original.call(id)&.merge(sign_authn_request: true, cert: "", fingerprint: "")
        end
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
        expect(response).to have_http_status(:forbidden)
        expect(c18_saml_response_xml).to be_nil
      ensure
        SamlIdp.config.service_provider.finder = original
      end

      it "a guest cannot obtain an assertion without credentials" do
        post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
        expect(c18_saml_response_xml).to be_nil
      end
    end

    context "wiki-server staff gate (view only)" do
      let(:wiki_request) { c18_authn_request(issuer: "wiki-server.makerepo.com", acs: "https://wiki-server.makerepo.com/acs") }

      it "tells a non-staff user they cannot log in to the wiki and renders no SAMLResponse form" do
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: wiki_request, submit: "current_user" }
        expect(response.body).to include("not habilitated to login to the wiki")
        expect(c18_saml_response_xml).to be_nil
      end

      it "lets staff through to the ACS" do
        c18_sign_in(:staff)
        post "/saml/auth", params: { SAMLRequest: wiki_request, submit: "current_user" }
        expect(c18_form_action).to eq("https://wiki-server.makerepo.com/acs")
        expect(c18_saml_response_xml).to be_present
      end
    end

    context "CSRF" do
      around do |example|
        original = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = original
      end

      it "rejects a POST without an authenticity token (this controller enforces CSRF, unlike the app-wide declaration)" do
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(c18_saml_response_xml).to be_nil
      end
    end
  end
end
