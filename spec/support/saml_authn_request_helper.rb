# frozen_string_literal: true

require "zlib"
require "base64"

# Builds SP-style (HTTP-Redirect binding) SAML requests for request specs.
# Include in the describe blocks that need it. The ACS is a method, not a
# constant: constants defined inside RSpec blocks leak to Object and are not
# resolved through included modules from inside examples.
module SamlAuthnRequestHelper
  # Wiki.js service provider's AssertionConsumerServiceURL (config/saml).
  def wikijs_acs
    "https://wikijs.makerepo.com/login/258365f7-0b23-403c-817a-5d1ca2be771f/callback"
  end

  # Raw-deflate + base64, as the HTTP-Redirect binding sends it.
  def saml_deflate(xml)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflated = deflater.deflate(xml, Zlib::FINISH)
    deflater.close
    Base64.strict_encode64(deflated)
  end

  # A deflated + base64 AuthnRequest.
  def authn_request(issuer: "wikijs.makerepo.com", acs: wikijs_acs, id: "_req1")
    xml = %(<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ) +
          %(xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="#{id}" Version="2.0" ) +
          %(IssueInstant="2026-03-10T15:00:00Z" AssertionConsumerServiceURL="#{acs}">) +
          %(<saml:Issuer>#{issuer}</saml:Issuer></samlp:AuthnRequest>)
    saml_deflate(xml)
  end
end
