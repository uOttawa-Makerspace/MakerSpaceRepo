class Badge < ActiveRecord::Base
  belongs_to :user
  belongs_to :badge_template

  def self.get_badge_image(badge_id)
    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badge_templates/'+badge_id,
                           :user => Rails.application.secrets.acclaim_api || ENV.fetch("acclaim_api"),
                           :password => '',
                           :headers => {"Content-type" => "application/json"}
      )
      return JSON.parse(response.body)['data']['image_url']
    rescue
      return nil
    end
  end

  def self.filter_by_attribute(value)
    if value
      if value == "search="
        default_scoped
      else
        value = value.split("=").last
        where("LOWER(description) like LOWER(?) OR
                 LOWER(issued_to) like LOWER(?)", "%#{value}%", "%#{value}%")
      end
    else
      default_scoped
    end
  end

  def self.acclaim_api_get_all_badges
    response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/high_volume_issued_badge_search',
                         :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                         :password => '',
                         :headers => {"Content-type" => "application/json"})
    JSON.parse(response.body)
  end
end