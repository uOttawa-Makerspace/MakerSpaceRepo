# frozen_string_literal: true
SamlIdp.configure do |config|
  config.x509_certificate = IO.read(File.join(Rails.root, "certs/saml.crt"))
  config.secret_key = IO.read(File.join(Rails.root, "certs/saml.key"))

  service_providers = {
    "wiki.makerepo.com" => {
      metadata_url:
        "https://wiki.makerepo.com/saml/module.php/saml/sp/metadata.php/wiki.makerepo.com",
      response_hosts: %w[
        en.wiki.makerepo.com
        fr.wiki.makerepo.com
        staff.makerepo.com
      ]
    },
    "rooms.makerepo.com" => {
      metadata_url: "https://rooms.makerepo.com/users/auth/saml/metadata",
      response_hosts: %w[rooms.makerepo.com]
    },
    "print.makerepo.com" => {
      metadata_url: "https://print.makerepo.com/saml/metadata",
      response_hosts: %w[print.makerepo.com localhost]
    },
    "wiki-server.makerepo.com" => {
      metadata_url: "https://makerepo.com/saml/wiki_metadata",
      response_hosts: %w[wiki-server.makerepo.com localhost]
    }
  }

  # principal is passed in when `encode_response` is called
  config.name_id.formats = {
    persistent: ->(principal) { principal.id },
    transient: ->(principal) { principal.username },
    email_address: ->(principal) { principal.email }
  }

  # extra attributes sent along with SAML response
  config.attributes = {
    email_address: {
      getter: ->(principal) { principal.email }
    },
    username: {
      getter: ->(principal) { principal.username }
    },
    name: {
      getter: ->(principal) { principal.name }
    },
    is_staff: {
      getter: ->(principal) { principal.staff? }
    },
    is_admin: {
      getter: ->(principal) { principal.admin? }
    },
    is_volunteer: {
      getter: ->(principal) { principal.volunteer? }
    },
    role: {
      getter: ->(principal) { principal.role }
    },
    avatar_transient_url: {
      getter: ->(principal) { principal.avatar.attachment&.url }
    },
    avatar_content_type: {
      getter: ->(principal) { principal.avatar.attachment&.content_type }
    }
  }

  config.service_provider.finder = ->(issuer_or_entity_id) do
    service_providers[issuer_or_entity_id]
  end
end
