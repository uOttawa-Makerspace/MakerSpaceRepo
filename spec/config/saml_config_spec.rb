# frozen_string_literal: true
require "rails_helper"

RSpec.describe "SamlConfig", type: :configuration do
  it "has the expected service providers" do
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
      },
      "wikijs.makerepo.com" => {
        metadata_url: "https://wikijs.makerepo.com/login/saml/metadata",
        response_hosts: %w[wikijs.makerepo.com],
        acs_url: "https://wikijs.makerepo.com/login/258365f7-0b23-403c-817a-5d1ca2be771f/callback"
      }
    }

    service_providers.each do |name, params|
      service_provider = SamlIdp.config.service_provider.finder.call(name)

      expect(service_provider).not_to be_nil
      expect(service_provider[:metadata_url]).to eq(params[:metadata_url])
      expect(service_provider[:response_hosts]).to eq(params[:response_hosts])
    end
  end

  it "has expected identification information" do
    principal = FactoryBot.create(:user)

    attributes = {
      persistent: principal.id,
      transient: principal.username,
      email_address: principal.email
    }

    # we want a specific order here
    expect(SamlIdp.config.name_id.formats.keys).to eq(attributes.keys)

    SamlIdp.config.name_id.formats.each do |key, lambda|
      value = lambda.call(principal)

      expect(value).to eq(attributes[key])
    end
  end

  it "has expected attributes" do
    principal = FactoryBot.create(:user)

    attributes = {
      email_address: principal.email,
      email: principal.email,
      username: principal.username,
      name: principal.name,
      displayName: principal.name,
      is_staff: principal.staff?,
      is_admin: principal.admin?,
      is_volunteer: principal.volunteer?,
      role: principal.role,
      avatar_transient_url: principal.avatar.attachment&.service_url,
      avatar_content_type: principal.avatar.attachment&.content_type
    }

    expect(SamlIdp.config.attributes.keys.sort).to eq(attributes.keys.sort)

    SamlIdp.config.attributes.each do |key, attribute|
      value = attribute[:getter].call(principal)

      expect(value).to eq attributes[key]
    end
  end
end