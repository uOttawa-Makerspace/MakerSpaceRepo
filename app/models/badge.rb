class Badge < ActiveRecord::Base
  belongs_to :user

  def self.get_badge_name(badge_id)
    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badge_templates/'+badge_id,
                           :user => Rails.application.secrets.acclaim_api,
                           :password => '',
                           :headers => {"Content-type" => "application/json"}
      )
      return JSON.parse(response.body)['data']['name']
    rescue
      return nil
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
