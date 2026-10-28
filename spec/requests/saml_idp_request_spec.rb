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

  def c18_logout_request(issuer: "rooms.makerepo.com", id: "_logout1")
    xml = %(<samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ) +
          %(xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="#{id}" Version="2.0" ) +
          %(IssueInstant="2026-03-10T15:00:00Z"><saml:Issuer>#{issuer}</saml:Issuer>) +
          %(<saml:NameID>x</saml:NameID></samlp:LogoutRequest>)
    c18_deflate(xml)
  end

  def c18_deflate(xml)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflated = deflater.deflate(xml, Zlib::FINISH)
    deflater.close
    Base64.strict_encode64(deflated)
  end

  # Registers a certificate + fingerprint for every SP, requires signed AuthnRequests
  # and gives them a logout endpoint, for the duration of the block.
  def c18_with_signing_sps(cert_pem: "not a certificate")
    original = SamlIdp.config.service_provider.finder
    SamlIdp.config.service_provider.finder = lambda do |id|
      original.call(id)&.merge(sign_authn_request: true, cert: cert_pem, fingerprint: "aa:bb",
                               assertion_consumer_logout_service_url: "https://rooms.makerepo.com/logout")
    end
    yield
  ensure
    SamlIdp.config.service_provider.finder = original
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

    it "does not write into the global attribute config while building the metadata" do
      original = SamlIdp.config.attributes
      SamlIdp.config.attributes = original.transform_values { |opts| opts.except(:friendly_name) }
      begin
        get "/saml/metadata"
        expect(response).to have_http_status(:ok)
        expect(SamlIdp.config.attributes.values.flat_map(&:keys)).not_to include(:friendly_name)
      ensure
        SamlIdp.config.attributes = original # no leakage into other examples
      end
    end

    it "uses the same value for the assertion Issuer and the metadata entityID when SAML_IDP_BASE_URL is set" do
      stub_const("ENV", ENV.to_h.merge("SAML_IDP_BASE_URL" => "https://makerepo.com/"))
      get "/saml/metadata"
      entity_id = Nokogiri::XML(response.body).root["entityID"]
      c18_sign_in(:regular)
      post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
      doc = Nokogiri::XML(c18_saml_response_xml)
      doc.remove_namespaces!
      expect(doc.at_xpath("//Assertion/Issuer").text).to eq(entity_id)
      expect(entity_id).to eq("https://makerepo.com/saml/auth")
    end

    it "does not double a mount prefix: SCRIPT_NAME=/app with SAML_IDP_BASE_URL=https://host/app" do
      stub_const("ENV", ENV.to_h.merge("SAML_IDP_BASE_URL" => "https://host/app"))
      get "/saml/metadata", env: { "SCRIPT_NAME" => "/app" }
      expect(Nokogiri::XML(response.body).root["entityID"]).to eq("https://host/app/saml/auth")
    end

    it "keeps the assertion Issuer the request URL when SAML_IDP_BASE_URL is unset" do
      c18_sign_in(:regular)
      post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
      doc = Nokogiri::XML(c18_saml_response_xml)
      doc.remove_namespaces!
      expect(doc.at_xpath("//Assertion/Issuer").text).to eq("http://www.example.com/saml/auth")
    end
  end

  describe "GET /saml/wiki_metadata" do
    let(:tracked) { Rails.root.join("config/saml/wiki_metadata.xml") }
    let(:legacy) { Rails.root.join("public/assets/metadata.xml") }

    def with_files(tracked_content: nil, legacy_content: nil)
      paths = { tracked => tracked_content, legacy => legacy_content }
      backups = paths.keys.to_h { |f| [f, f.exist? ? f.read : nil] }
      paths.each do |f, content|
        FileUtils.mkdir_p(f.dirname) if content
        content ? f.write(content) : FileUtils.rm_f(f)
      end
      yield
    ensure
      backups.each { |f, old| old ? f.write(old) : FileUtils.rm_f(f) }
    end

    it "serves the tracked config/saml/wiki_metadata.xml as application/xml" do
      with_files(tracked_content: "<EntityDescriptor entityID=\"tracked\"/>", legacy_content: "<legacy/>") do
        get "/saml/wiki_metadata"
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/xml")
        expect(response.body).to eq("<EntityDescriptor entityID=\"tracked\"/>")
      end
    end

    it "falls back to the hand-placed public/assets/metadata.xml" do
      with_files(legacy_content: "<EntityDescriptor entityID=\"wiki-server\"/>") do
        get "/saml/wiki_metadata"
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("<EntityDescriptor entityID=\"wiki-server\"/>")
      end
    end

    it "is a 404 (logged), not a 500, when no metadata file exists (D-R17)" do
      with_files do
        expect(Rails.logger).to receive(:error).with(/SAML wiki metadata not found/)
        get "/saml/wiki_metadata"
        expect(response).to have_http_status(:not_found)
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

    it "keeps a redirect-binding Signature/SigAlg through the login form so the credential POST still validates" do
      key = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new.tap do |c|
        c.version = 2
        c.serial = 1
        c.subject = c.issuer = OpenSSL::X509::Name.parse("/CN=sp.test")
        c.public_key = key.public_key
        c.not_before = 1.day.ago
        c.not_after = 1.day.from_now
        c.sign(key, OpenSSL::Digest.new("SHA256"))
      end
      original = SamlIdp.config.service_provider.finder
      SamlIdp.config.service_provider.finder = lambda do |id|
        original.call(id)&.merge(sign_authn_request: true, cert: cert.to_pem, fingerprint: "aa:bb")
      end
      saml_request = c18_authn_request
      sig_alg = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      signed = "SAMLRequest=#{CGI.escape(saml_request)}&RelayState=rs1&SigAlg=#{CGI.escape(sig_alg)}"
      signature = Base64.strict_encode64(key.sign(OpenSSL::Digest.new("SHA256"), signed))
      query = { SAMLRequest: saml_request, RelayState: "rs1", SigAlg: sig_alg, Signature: signature }

      get "/saml/auth", params: query
      expect(response).to have_http_status(:ok)
      action = Rack::Utils.parse_query(URI(c18_form_action).query)
      expect(action).to include("Signature" => signature, "SigAlg" => sig_alg)

      user = create(:user, :regular_user, password: BCrypt::Password.create(password))
      post c18_form_action, params: { submit: "sign_in", username: user.username, password: password }
      expect(response).to have_http_status(:ok)
      expect(c18_saml_response_xml).to be_present
    ensure
      SamlIdp.config.service_provider.finder = original
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

      it "shares one budget with the HTML login: 6 HTML + 5 SAML attempts from one IP: the 11th is a 429" do
        6.times { post login_authentication_path, params: { username_email: user.username, password: "wrong" } }
        expect(response).not_to have_http_status(:too_many_requests)
        4.times do
          post_auth(submit: "sign_in", username: user.username, password: "wrong")
          expect(response).to have_http_status(:ok)
        end
        post_auth(submit: "sign_in", username: user.username, password: password) # the 11th attempt
        expect(response).to have_http_status(:too_many_requests)
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

    it "answers 400 for a Signature without SigAlg or non-string binding params" do
      c18_sign_in(:regular)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: c18_authn_request, Signature: "c2ln" }
      expect(response).to have_http_status(:bad_request)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: c18_authn_request, RelayState: ["x"] }
      expect(response).to have_http_status(:bad_request)
    end

    it "does not swallow a server failure as a 400" do
      c18_sign_in(:regular)
      allow_any_instance_of(SamlIdp::Request).to receive(:valid?).and_raise(ActiveRecord::ConnectionNotEstablished)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: c18_authn_request }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "answers 400 when the gem raises its SignedDocument::ValidationError outside the guard" do
      allow_any_instance_of(SamlIdp::Request).to receive(:valid?).and_raise(SamlIdp::XMLSecurity::SignedDocument::ValidationError, "Digest mismatch")
      c18_sign_in(:regular)
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: c18_authn_request }
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 400 when the payload is malformed in a way the gem raises (bad ACS URL)" do
      c18_sign_in(:regular)
      bad = c18_authn_request(issuer: "rooms.makerepo.com", acs: "https://rooms.makerepo.com/a b")
      post "/saml/auth", params: { submit: "current_user", SAMLRequest: bad }
      expect(response).to have_http_status(:bad_request)
    end

    context "signature verification failures are refused (403), never a 500" do
      def ds = "http://www.w3.org/2000/09/xmldsig#"

      before { SamlSignatureGuard.reset_certificate_checks! }

      def signed_logout(signature_xml, extra: "", id: "_lo1")
        c18_deflate(%(<samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ) +
                    %(xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="#{id}" Version="2.0" ) +
                    %(IssueInstant="2026-03-10T15:00:00Z"><saml:Issuer>rooms.makerepo.com</saml:Issuer>) +
                    %(<saml:NameID>x</saml:NameID>#{extra}#{signature_xml}</samlp:LogoutRequest>))
      end

      def full_signature(key_info: "", digest_method: %(<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>),
                         digest_value: "<ds:DigestValue>AAAA</ds:DigestValue>", signature_value: "<ds:SignatureValue>AAAA</ds:SignatureValue>",
                         reference_uri: "#_lo1", transforms: "", reference_outside: "")
        %(<ds:Signature xmlns:ds="#{ds}"><ds:SignedInfo><ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>) +
          %(<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>) +
          (reference_outside.empty? ? %(<ds:Reference URI="#{reference_uri}">#{transforms}#{digest_method}#{digest_value}</ds:Reference>) : "") +
          %(</ds:SignedInfo>#{reference_outside}#{signature_value}#{key_info}</ds:Signature>)
      end

      def post_logout(request)
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: request, submit: "logout" }
      end

      {
        "no SignedInfo" => -> { %(<ds:Signature xmlns:ds="#{ds}"><ds:SignatureValue>AAAA</ds:SignatureValue></ds:Signature>) },
        "an empty SignatureValue" => -> { full_signature(signature_value: "<ds:SignatureValue/>") },
        "an empty DigestValue" => -> { full_signature(digest_value: "<ds:DigestValue/>") },
        "a missing DigestValue" => -> { full_signature(digest_value: "") },
        "a Reference outside SignedInfo" => -> {
          full_signature(reference_outside: %(<ds:Reference URI="#_lo1"><ds:DigestValue>AAAA</ds:DigestValue></ds:Reference>))
        },
        "a DigestMethod without Algorithm" => -> { full_signature(digest_method: "<ds:DigestMethod/>") },
        "InclusiveNamespaces without PrefixList" => -> {
          full_signature(transforms: %(<ds:Transforms><ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"><ec:InclusiveNamespaces xmlns:ec="http://www.w3.org/2001/10/xml-exc-c14n#"/></ds:Transform></ds:Transforms>))
        },
        "an empty X509Certificate" => -> {
          full_signature(key_info: %(<ds:KeyInfo><ds:X509Data><ds:X509Certificate/></ds:X509Data></ds:KeyInfo>))
        },
        "a garbage embedded certificate" => -> {
          full_signature(key_info: %(<ds:KeyInfo><ds:X509Data><ds:X509Certificate>bm90IGEgY2VydA==</ds:X509Certificate></ds:X509Data></ds:KeyInfo>))
        },
        "a Reference to an ID that does not exist" => -> { full_signature(reference_uri: "#nope") },
        "an empty Reference URI" => -> { full_signature(reference_uri: "") }
      }.each do |shape, build|
        it "a LogoutRequest with #{shape}" do
          c18_with_signing_sps do
            post_logout(signed_logout(instance_exec(&build)))
            expect(response).to have_http_status(:forbidden)
          end
        end
      end

      it "XML REXML cannot parse but Nokogiri recovers is a 400 (malformed input)" do
        c18_with_signing_sps do
          post_logout(signed_logout(full_signature, extra: "<junk a='1' a='2'/>"))
          expect(response).to have_http_status(:bad_request)
        end
      end

      it "an SP that does not require signatures still gets its assertion with an odd ds:Signature in the request" do
        odd = full_signature(reference_uri: "")
        xml = %(<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ) +
              %(ID="_req1" Version="2.0" IssueInstant="2026-03-10T15:00:00Z" AssertionConsumerServiceURL="#{WIKIJS_ACS}">) +
              %(<saml:Issuer>wikijs.makerepo.com</saml:Issuer>#{odd}</samlp:AuthnRequest>)
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: c18_deflate(xml), submit: "current_user" }
        expect(response).to have_http_status(:ok)
        expect(c18_saml_response_xml).to be_present
        get "/saml/auth", params: { SAMLRequest: c18_deflate(xml) }
        expect(response).to have_http_status(:ok)
      end

      context "with a real signature" do
        let(:key) { OpenSSL::PKey::RSA.new(2048) }
        let(:cert) do
          OpenSSL::X509::Certificate.new.tap do |c|
            c.version = 2
            c.serial = 1
            c.subject = c.issuer = OpenSSL::X509::Name.parse("/CN=sp.test")
            c.public_key = key.public_key
            c.not_before = 1.day.ago
            c.not_after = 1.day.from_now
            c.sign(key, OpenSSL::Digest.new("SHA256"))
          end
        end
        # the gem decodes the configured certificate as base64 DER
        let(:cert_b64) { Base64.strict_encode64(cert.to_der) }

        # Signs the element with the given ID (exclusive c14n, rsa-sha256) and returns the XML
        # of an enveloped ds:Signature for it, computed over the document WITHOUT the signature.
        def signature_for(xml, signed_id, reference_uri: "##{signed_id}")
          doc = Nokogiri::XML(xml)
          target = doc.at_xpath("//*[@ID='#{signed_id}']")
          digest = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(target.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)))
          signed_info = %(<ds:SignedInfo xmlns:ds="#{ds}"><ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>) +
                        %(<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>) +
                        %(<ds:Reference URI="#{reference_uri}"><ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>) +
                        %(<ds:DigestValue>#{digest}</ds:DigestValue></ds:Reference></ds:SignedInfo>)
          canonical = Nokogiri::XML(signed_info).root.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)
          sig = Base64.strict_encode64(key.sign(OpenSSL::Digest.new("SHA256"), canonical))
          %(<ds:Signature xmlns:ds="#{ds}">#{signed_info}<ds:SignatureValue>#{sig}</ds:SignatureValue></ds:Signature>)
        end

        def logout_xml(inner, id: "_lo1", lead: "", issuer: "rooms.makerepo.com")
          %(<samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ) +
            %(ID="#{id}" Version="2.0" IssueInstant="2026-03-10T15:00:00Z">#{lead}<saml:Issuer>#{issuer}</saml:Issuer>) +
            %(<saml:NameID>x</saml:NameID>#{inner}</samlp:LogoutRequest>)
        end

        it "accepts a LogoutRequest whose root element is signed (control for the wrapping examples)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            unsigned = logout_xml("")
            post_logout(c18_deflate(logout_xml(signature_for(unsigned, "_lo1"))))
            expect(response).to have_http_status(:ok)
          end
        end

        it "refuses a wrapped document: a validly signed element elsewhere, an unsigned root request (403)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            extra = %(<Extension ID="signed1">harmless</Extension>)
            body = logout_xml(extra)
            wrapped = logout_xml(extra + signature_for(body, "signed1"))
            # control: the signature itself verifies against the configured cert
            expect(Saml::XML::Document.parse(wrapped).valid_signature?(cert_b64, "")).to be(true)
            post_logout(c18_deflate(wrapped))
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "refuses an XPath-injection root ID that makes the gem digest a nested signed element (403)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            root_id = "x' or @ID='s1"
            extra = %(<Extension ID="s1">harmless</Extension>)
            wrapped = logout_xml(extra + signature_for(logout_xml(extra, id: root_id), "s1", reference_uri: "##{root_id}"), id: root_id)
            # control: the gem itself accepts this unsigned-root document
            expect(Saml::XML::Document.parse(wrapped).valid_signature?(cert_b64, "")).to be(true)
            post_logout(c18_deflate(wrapped))
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "refuses a foreign-namespace root named LogoutRequest wrapping a nested samlp:LogoutRequest (403)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            foreign = lambda do |inner|
              %(<LogoutRequest xmlns="urn:example:foreign" ID="_lo1">#{logout_xml('', id: '_nested')}#{inner}</LogoutRequest>)
            end
            wrapped = foreign.call(signature_for(foreign.call(""), "_lo1"))
            expect(Saml::XML::Document.parse(wrapped).valid_signature?(cert_b64, "")).to be(true)
            post_logout(c18_deflate(wrapped))
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "refuses an Issuer smuggled into ds:Object ahead of the real one (403)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            sig = signature_for(logout_xml("", issuer: "wikijs.makerepo.com"), "_lo1")
            evil = sig.sub("</ds:Signature>", %(<ds:Object><saml:Issuer>rooms.makerepo.com</saml:Issuer></ds:Object></ds:Signature>))
            wrapped = logout_xml("", lead: evil, issuer: "wikijs.makerepo.com")
            expect(Saml::XML::Document.parse(wrapped).valid_signature?(cert_b64, "")).to be(true)
            expect(Saml::XML::Document.parse(wrapped).at_xpath("//saml:Issuer", saml: "urn:oasis:names:tc:SAML:2.0:assertion").text).to eq("rooms.makerepo.com")
            post_logout(c18_deflate(wrapped))
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "does not turn an infrastructure failure inside the verification into a 403" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            allow_any_instance_of(SamlIdp::XMLSecurity::SignedDocument).to receive(:validate).and_raise(ActiveRecord::ConnectionNotEstablished)
            post_logout(c18_deflate(logout_xml(signature_for(logout_xml(""), "_lo1"))))
            expect(response).to have_http_status(:internal_server_error)
          end
        end

        it "treats attacker-supplied Signature bytes that raise in OpenSSL as an invalid signature, not an SP misconfiguration" do
          c18_with_signing_sps(cert_pem: cert.to_pem) do
            allow_any_instance_of(OpenSSL::PKey::RSA).to receive(:verify).and_raise(OpenSSL::PKey::PKeyError, "bad signature bytes")
            expect(Rails.error).not_to receive(:report)
            c18_sign_in(:regular)
            post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user", Signature: Base64.strict_encode64("sig"),
                                         SigAlg: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" }
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "refuses a document with two signatures (403)" do
          c18_with_signing_sps(cert_pem: cert_b64) do
            unsigned = logout_xml("")
            sig = signature_for(unsigned, "_lo1")
            post_logout(c18_deflate(logout_xml(sig + sig)))
            expect(response).to have_http_status(:forbidden)
          end
        end
      end

      it "reports a broken SP certificate once, however often the request is replayed" do
        c18_with_signing_sps(cert_pem: "not a certificate") do
          expect(Rails.error).to receive(:report).once
          c18_sign_in(:regular)
          3.times do
            post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user", Signature: Base64.strict_encode64("sig"),
                                         SigAlg: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" }
            expect(response).to have_http_status(:forbidden)
          end
        end
      end

      it "a broken SP certificate refuses the request (403) and is reported at error level" do
        c18_with_signing_sps(cert_pem: "not a certificate") do
          expect(Rails.error).to receive(:report).with(instance_of(OpenSSL::X509::CertificateError), hash_including(severity: :error)).once
          c18_sign_in(:regular)
          post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user", Signature: Base64.strict_encode64("sig"),
                                       SigAlg: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" }
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context "SECURITY: blank Signature / SigAlg must not skip the gem's signature checks" do
      it "refuses a LogoutRequest with an empty Signature= (400), without signing the user out" do
        c18_with_signing_sps do
          user = c18_sign_in(:regular)
          [{ Signature: "", SigAlg: "" },
           { Signature: "", SigAlg: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" },
           { Signature: "c2ln", SigAlg: "" },
           { SigAlg: "" }].each do |blank|
            post "/saml/auth", params: { SAMLRequest: c18_logout_request, submit: "logout" }.merge(blank)
            expect(response).to have_http_status(:bad_request)
          end
          post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user" }
          expect(response).to have_http_status(:forbidden) # (unsigned) still refused, and the session survived
          expect(session[:user_id]).to eq(user.id)
        end
      end

      it "refuses an unsigned LogoutRequest outright (403)" do
        c18_with_signing_sps do
          c18_sign_in(:regular)
          post "/saml/auth", params: { SAMLRequest: c18_logout_request, submit: "logout" }
          expect(response).to have_http_status(:forbidden)
        end
      end

      it "refuses a signing-SP AuthnRequest with an empty Signature= (400), never an assertion" do
        c18_with_signing_sps do
          c18_sign_in(:regular)
          post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user", Signature: "", SigAlg: "" }
          expect(response).to have_http_status(:bad_request)
          expect(c18_saml_response_xml).to be_nil
        end
      end

      it "never carries a blank Signature/SigAlg forward in the login form" do
        get "/saml/auth", params: { SAMLRequest: c18_authn_request }
        query = Rack::Utils.parse_query(URI(c18_form_action).query)
        expect(query.keys).not_to include("Signature", "SigAlg")
      end
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

      it "refuses with 403 when the gem reports an error but still returns a truthy verdict (unparseable SP certificate)" do
        original = SamlIdp.config.service_provider.finder
        SamlIdp.config.service_provider.finder = lambda do |id|
          original.call(id)&.merge(sign_authn_request: true, cert: "not a certificate", fingerprint: "aa:bb")
        end
        c18_sign_in(:regular)
        post "/saml/auth", params: { SAMLRequest: c18_authn_request, submit: "current_user", Signature: Base64.strict_encode64("sig"),
                                     SigAlg: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" }
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
