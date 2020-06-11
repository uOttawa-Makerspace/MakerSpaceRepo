namespace :badges do
  desc "Get all data from acclaim api"
  task get_data: [:environment, :get_and_update_badge_templates] do
    puts "Start updating badges..."
    begin
      data = Badge.acclaim_api_get_all_badges
      data['data'].each do |badges|
        if User.where(email: badges['recipient_email']).present? and badges['state'] != "revoked"
          user = User.find_by(email: badges['recipient_email'])
          new_badge = Badge.find_or_create_by(acclaim_badge_id: badges['id'], user: user)
          badge_template = BadgeTemplate.find_by_acclaim_template_id(badges['badge_template']['id'])
          values = {issued_to: badges['issued_to'],
                    acclaim_badge_id: badges['id'],
                    badge_url: badges['badge_url'],
                    badge_template_id: badge_template.id}
          new_badge.update_attributes(values)
          puts "#{new_badge.user.name}: Updated!"
        end
      end
    end
    puts "Done!"
  end

  desc "Get badge templates from Acclaim API"
  task get_and_update_badge_templates: :environment do
    puts "Starting..."
    data = BadgeTemplate.acclaim_api_get_all_badge_templates
    data['data'].each do |badge_template|
      bt = BadgeTemplate.find_or_create_by(acclaim_template_id: badge_template['id'])
      bt.update_attributes(badge_description: badge_template['description'], badge_name: badge_template['name'], image_url: badge_template['image_url'])
      puts "#{bt.badge_name}: Updated!"
    end
    puts "Done!"
  end
end
