# frozen_string_literal: true
SamlIdp.configure do |config|
  config.x509_certificate = IO.read(File.join(Rails.root, 'certs/saml.crt'))
  config.secret_key = IO.read(File.join(Rails.root, 'certs/saml.key'))

  service_providers = {
    'wiki.makerepo.com' => {
      metadata_url: 'https://wiki.makerepo.com/saml/module.php/saml/sp/metadata.php/wiki.makerepo.com',
      response_hosts: %w(en.wiki.makerepo.com fr.wiki.makerepo.com staff.makerepo.com)
    }
  }

  # principal is passed in when `encode_response` is called
  config.name_id.formats = {
    email_address: -> (principal) { principal.email },
    transient: -> (principal) { principal.username },
    persistent: -> (principal) { principal.id }
  }

  # extra attributes sent along with SAML response
  config.attributes = {
    email_address: {
      getter: -> (principal) { principal.email }
    },
    username: {
      getter: -> (principal) { principal.username }
    },
    name: {
      getter: -> (principal) { principal.name }
    },
    is_staff: {
      getter: -> (principal) { principal.staff? }
    },
    is_admin: {
      getter: -> (principal) { principal.admin? }
    },
    is_volunteer: {
      getter: -> (principal) { principal.volunteer? }
    }
  }

  config.service_provider.finder = -> (issuer_or_entity_id) { service_providers[issuer_or_entity_id] }
end