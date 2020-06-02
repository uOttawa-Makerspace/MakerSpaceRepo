class Badge < ActiveRecord::Base
  belongs_to :user
  belongs_to :badge_template

  def self.filter_by_attribute(value)
    if value
      if value == "search="
        default_scoped
      else
        value = value.split("=").last.gsub('+', ' ')
        where("LOWER(badge_templates.badge_name) like LOWER(?) OR
                 LOWER(issued_to) like LOWER(?) OR
                 LOWER(badge_templates.badge_description) like LOWER(?) OR
                 LOWER(badge_templates.acclaim_template_id) like LOWER(?)", "%#{value}%", "%#{value}%", "%#{value}%", "%#{value}%")
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

  def acclaim_api_delete_badge
    Excon.delete('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges/'+ self.acclaim_badge_id,
                 :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                 :password => '',
                 :headers => {"Content-type" => "application/json"})
  end

  def acclaim_api_revoke_badge
    Excon.put('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges/'+self.acclaim_badge_id+"/revoke",
              :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
              :password => '',
              :headers => {"Content-type" => "application/json"},
              :query => {:reason => "Admin revoked badge", :suppress_revoke_notification_email => false})
  end

  def self.acclaim_api_create_badge(user, acclaim_template_id)
    Excon.post('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges',
               :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
               :password => '',
               :headers => {"Content-type" => "application/json"},
               :query => {:recipient_email => user.email,
                          :badge_template_id => acclaim_template_id,
                          :issued_to_first_name => user.name.split(" ", 2)[0],
                          :issued_to_last_name => user.name.split(" ", 2)[1],
                          :issued_at => Time.now})
  end

end