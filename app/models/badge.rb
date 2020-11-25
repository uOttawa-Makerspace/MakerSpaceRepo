# frozen_string_literal: true

class Badge < ApplicationRecord
  belongs_to :user
  belongs_to :badge_template
  belongs_to :certification, optional: true

  def self.filter_by_attribute(value)
    if value
      if value == 'search='
        default_scoped
      else
        value = value.split('=').last.gsub('+', ' ')
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
    response = Excon.get("#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]}/v1/organizations/#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]}/high_volume_issued_badge_search",
                         user: Rails.application.credentials[Rails.env.to_sym][:acclaim][:api],
                         password: '',
                         headers: { 'Content-type' => 'application/json' })
    JSON.parse(response.body)
  end

  def acclaim_api_delete_badge
    Excon.delete("#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]}/v1/organizations/#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]}/badges/" + acclaim_badge_id,
                 user: Rails.application.credentials[Rails.env.to_sym][:acclaim][:api],
                 password: '',
                 headers: { 'Content-type' => 'application/json' })
  end

  def acclaim_api_revoke_badge
    Excon.put("#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]}/v1/organizations/#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]}/badges/" + acclaim_badge_id + '/revoke',
              user: Rails.application.credentials[Rails.env.to_sym][:acclaim][:api],
              password: '',
              headers: { 'Content-type' => 'application/json' },
              query: { reason: 'Admin revoked badge', suppress_revoke_notification_email: Rails.env.test? ? true : false })
  end

  def self.acclaim_api_create_badge(user, acclaim_template_id)
    Excon.post("#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:url]}/v1/organizations/#{Rails.application.credentials[Rails.env.to_sym][:acclaim][:organisation]}/badges",
               user: Rails.application.credentials[Rails.env.to_sym][:acclaim][:api],
               password: '',
               headers: { 'Content-type' => 'application/json' },
               query: { recipient_email: user.email,
                        badge_template_id: acclaim_template_id,
                        issued_to_first_name: user.name.split(' ', 2)[0],
                        issued_to_last_name: user.name.split(' ', 2)[1],
                        issued_at: Time.zone.now,
                        suppress_revoke_notification_email: Rails.env.test? ? true : false })
  end

  def self.create_badge(order_item_id)
    order_item = OrderItem.find(order_item_id)
    badge_template = order_item.proficient_project.badge_template
    user = order_item.order.user
    response = Badge.acclaim_api_create_badge(user, badge_template.acclaim_template_id)
    if response.status == 201
      badge_data = JSON.parse(response.body)['data']
      Badge.create(user_id: user.id,
                   issued_to: user.name,
                   acclaim_badge_id: badge_data['id'],
                   badge_template_id: badge_template.id)
      order_item.update(status: 'Awarded')
      flash[:notice] = 'The badge has been sent to the user !'
    else
      flash[:alert] = 'An error has occurred when creating the badge, this message might help : ' + JSON.parse(response.body)['data']['message']
    end
  end

  def create_certification
    user = self.user
    badge_template = self.badge_template
    return if (self.certification.present? || badge_template.blank? || badge_template.training.blank?)
    level = if badge_template.badge_name.include?('Advanced')
              'Advanced'
            elsif badge_template.badge_name.include?('Intermediate')
              'Intermediate'
            else
              'Beginner'
            end
    admin = if User.find_by(email: 'mtc@uottawa.ca').present?
              User.find_by(email: 'mtc@uottawa.ca')
            else
              User.find_by(role: 'admin')
            end

    cert = Certification.existent_certification(user, badge_template.training, level)
    unless cert.present?
      training_session = TrainingSession.create(user: admin, training: badge_template.training, level: level)
      training_session.users << user
      cert = training_session.certifications.create(user: user, training_session: training_session)
    end

    self.update(certification: cert)
  end
end
