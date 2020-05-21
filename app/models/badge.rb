class Badge < ActiveRecord::Base
  belongs_to :user

  def self.get_badge_name(badge_id)
    if BadgeTemplate.where(badge_id: badge_id).first.present?
      return BadgeTemplate.where(badge_id: badge_id).first.badge_name
    else
      return "Name not found"
    end
  end

  def self.get_badges_list
    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badge_templates',
                           :user => Rails.application.secrets.acclaim_api || ENV.fetch("acclaim_api"),
                           :password => '',
                           :headers => {"Content-type" => "application/json"}
      )
      badge_list = JSON.parse(response.body)['data']
    rescue
      badge_list = []
    end
    badge_list
  end
end
