# frozen_string_literal: true

class BadgeTemplate < ApplicationRecord
  include CredlyConcern

  has_many :badge_requirements, dependent: :destroy
  has_many :badges
  has_many :proficient_projects
  belongs_to :training, optional: true

  def self.acclaim_api_get_all_badge_templates
    JSON.parse credly_api_call(:get, endpoint: '/badge_templates').body
  end

  def acclaim_api_get_badge_template
    JSON.parse credly_api_call(:get, endpoint: "/badge_templates/#{acclaim_template_id}").body
  end
end
