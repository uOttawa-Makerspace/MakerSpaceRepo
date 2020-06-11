class BadgeTemplate < ActiveRecord::Base
  has_many :badge_requirements, dependent: :destroy
  has_many :badges
  has_many :proficient_projects

  def self.acclaim_api_get_all_badge_templates
    response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badge_templates',
                         :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                         :password => '',
                         :headers => {"Content-type" => "application/json"})
    JSON.parse(response.body)
  end

end
