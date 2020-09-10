# frozen_string_literal: true

class BadgeTemplate < ApplicationRecord
  has_many :badge_requirements, dependent: :destroy
  has_many :badges
  has_many :proficient_projects

  def self.acclaim_api_get_all_badge_templates
    response = Excon.get("#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]}/v1/organizations/#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]}/badge_templates",
                         user: Rails.application.credentials[Rails.env.to_sym][:acclaim][:api],
                         password: '',
                         headers: { 'Content-type' => 'application/json' })
    JSON.parse(response.body)
  end
end
