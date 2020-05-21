namespace :badges do
  desc "Get all data from acclaim api"
  task get_data: :environment do

    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/high_volume_issued_badge_search',
                           :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                           :password => '',
                           :headers => {"Content-type" => "application/json"}
      )
      data = JSON.parse(response.body)

      data['data'].each do |badges|

        if User.where(email: badges['recipient_email']).present?
          user = User.where(email: badges['recipient_email']).first
          if user.badges.where(badge_id: badges['id']).present? == false
            values = {user_id: user.id, username: user.username, image_url: badges['badge_template']['image']['url'], description: badges['badge_template']['description'], issued_to: badges['issued_to'], badge_id: badges['id'], badge_url: badges['badge_url']}
            Badge.create(values)
          elsif user.badges.where(badge_id: badges['id']).present? and user.badges.where(badge_url: badges['badge_url']).present? == false and badges['badge_url'] != ""
            Badge.update(user.badges.where(badge_id: badges['id']), :badge_url => badges['badge_url'])
          end
        end

      end

    end

  end
end
