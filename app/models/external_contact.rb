class ExternalContact < ApplicationRecord
  has_many :keys, as: :holder, dependent: :restrict_with_error
  has_many :key_transactions, as: :holder, dependent: :nullify

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :first_name, :last_name, with: ->(name) { name.strip }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :phone, format: { with: /\A[\d\-\+\(\)\s]*\z/ }, allow_blank: true

  def name
    "#{first_name} #{last_name}".strip
  end

  def self.find_or_create_by_details(first_name:, last_name:, email:, phone: nil)
    normalized = email.to_s.strip.downcase
    attempts = 0

    begin
      contact = find_or_initialize_by(email: normalized)
      contact.first_name = first_name
      contact.last_name  = last_name
      contact.phone      = phone if phone.present?
      contact.save!
      contact
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts <= 2
      find_by!(email: normalized)
    end
  end
end