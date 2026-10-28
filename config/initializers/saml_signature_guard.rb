# frozen_string_literal: true

# Hardening around the saml_idp gem's request-signature verification. Prepended to
# SamlIdp::Request and active ONLY when a signature is actually being verified (every
# LogoutRequest, and AuthnRequests from SPs configured with sign_authn_request).
# Requests from SPs that do not require signatures never reach this code's checks.
#
#  * What the gem's XML walk and crypto raise while verifying (VERIFICATION_FAILURES)
#    means the signature is not valid: the gem dereferences the parts of the XML
#    signature without nil checks, so a crafted document raises NoMethodError and friends. The request is refused (the gem's
#    `valid?` then answers false, the controller 403s) instead of a 500.
#    Client-input parse errors are re-raised: the controller answers those with 400.
#  * Signature wrapping: exactly one ds:Signature, and every Reference must point at the
#    ID of the root AuthnRequest/LogoutRequest, the element the gem reads Issuer and
#    ACS URL from. The gem only checks that the referenced ID exists *somewhere*.
#  * A broken SP certificate (configuration, not the request) is refused as well but
#    also reported through Rails.error so it is visible.
module SamlSignatureGuard
  # Raised for malformed input; the controller maps these to 400.
  PARSE_ERRORS = [
    Zlib::Error, Nokogiri::XML::SyntaxError, URI::InvalidURIError, REXML::ParseException
  ].freeze

  # xsd:ID / NCName. The gem interpolates the Reference URI unescaped into an XPath
  # (//*[@ID='...']), so any other root ID could smuggle XPath syntax in.
  VALID_ID = /\A[A-Za-z_][A-Za-z0-9_.-]*\z/

  SAML_PROTOCOL = "urn:oasis:names:tc:SAML:2.0:protocol"
  SAML_ASSERTION = "urn:oasis:names:tc:SAML:2.0:assertion"

  DSIG = { "ds" => "http://www.w3.org/2000/09/xmldsig#" }.freeze

  CERTIFICATE_CHECKS = Concurrent::Map.new

  # For specs: forget what has been parsed and reported.
  def self.reset_certificate_checks!
    CERTIFICATE_CHECKS.clear
  end

  def valid_signature?
    return super unless verifying_signature?
    return false unless covers_root_request?

    guarded("embedded") { super }
  end

  def valid_external_signature?
    return super unless verifying_signature?
    return false unless sp_certificate_parses?

    guarded("external") { super }
  end

  private

  def verifying_signature?
    logout_request? || (authn_request? && validate_auth_request_signature?)
  end

  # What the gem's XML walk and crypto raise for a crafted document: nil dereferences
  # (NoMethodError, TypeError), bad arguments, OpenSSL failures and its own
  # ValidationError. Wraps only the gem's call; DB, network and metadata-getter
  # failures (and real bugs of other kinds) propagate as 500s and reach Rails.error.
  VERIFICATION_FAILURES = [
    NoMethodError, TypeError, ArgumentError, OpenSSL::OpenSSLError,
    SamlIdp::XMLSecurity::SignedDocument::ValidationError
  ].freeze

  def guarded(kind)
    yield
  rescue *VERIFICATION_FAILURES => e
    log("#{kind} signature check failed for issuer #{issuer.to_s.truncate(200).inspect}: #{e.class}")
    if sp_config_fault?(e)
      Rails.error.report(e, handled: true, severity: :error, context: { saml_service_provider: issuer.to_s.truncate(200) })
    end
    false
  end

  # Only a configured certificate that itself fails to parse is a misconfiguration.
  # Any other OpenSSL failure (e.g. a PKeyError from attacker-supplied Signature bytes)
  # is just an invalid signature.
  def sp_config_fault?(error)
    error.is_a?(OpenSSL::OpenSSLError) && !configured_certificate_parses?
  end

  # The embedded check hands the gem a base64 DER certificate, the external one PEM/DER.
  def configured_certificate_parses?
    cached_certificate_check(:lenient) do |cert|
      [cert, Base64.decode64(cert)].any? do |candidate|
        OpenSSL::X509::Certificate.new(candidate)
        true
      rescue OpenSSL::X509::CertificateError
        false
      end
    end
  end

  def sp_certificate_parses?
    parses = cached_certificate_check(:strict) do |cert|
      OpenSSL::X509::Certificate.new(cert)
      true
    rescue OpenSSL::X509::CertificateError
      false
    end
    log("service provider #{issuer.to_s.truncate(200).inspect} has an unparseable certificate") unless parses
    parses
  end

  # The parse result is memoized per process, per certificate (the finder's value, not
  # request data), and a broken certificate is reported to Rails.error exactly once, so
  # an unauthenticated client cannot flood the error tracker by replaying a request.
  def cached_certificate_check(mode)
    cert = service_provider.cert.to_s
    SamlSignatureGuard::CERTIFICATE_CHECKS.compute_if_absent([mode, Digest::SHA256.hexdigest(cert)]) do
      parses = yield(cert)
      unless parses
        Rails.error.report(OpenSSL::X509::CertificateError.new("SP certificate does not parse"), handled: true, severity: :error,
                           context: { saml_service_provider: issuer.to_s.truncate(200) })
      end
      parses
    end
  end

  # The gem verifies a REXML parse of the re-serialized document, not the Nokogiri one;
  # count the signatures the way it sees them so a parser differential cannot hide one.
  # (REXML::ParseException is in PARSE_ERRORS: the controller answers 400.)
  def rexml_signature_count
    REXML::XPath.match(REXML::Document.new(document.to_xml), "//ds:Signature", DSIG).size
  end

  # What the gem will act on must be exactly what the (single) signature covers:
  #  * the root is the SAML-protocol AuthnRequest/LogoutRequest, and is the very node the
  #    gem's own `//samlp:...` XPath returns (a foreign-namespace root of the same name
  #    could otherwise wrap a nested, different request);
  #  * the Issuer the gem reads (the first `//saml:Issuer`) is a direct child of that
  #    root, so it is covered by the digest (not inside ds:Signature/ds:Object/ds:KeyInfo,
  #    which the digest does not cover).
  def covers_root_request?
    # The gem's own memoized Nokogiri parse of raw_xml: the node identity checks below
    # only mean something against the very document its XPath lookups run on.
    doc = document
    root = doc.root
    return false unless root && root.namespace&.href == SAML_PROTOCOL && %w[AuthnRequest LogoutRequest].include?(root.name)
    return false unless root["ID"].to_s.match?(VALID_ID)
    return false unless request == root

    first_issuer = doc.at_xpath("//saml:Issuer", "saml" => SAML_ASSERTION)
    return false unless first_issuer && first_issuer.parent == root
    return false unless doc.xpath("//ds:Signature", DSIG).size == 1 && rexml_signature_count == 1

    references = doc.xpath("//ds:Reference", DSIG)
    references.any? && references.all? { |ref| ref["URI"] == "##{root['ID']}" }
  end
end

SamlIdp::Request.prepend(SamlSignatureGuard)
