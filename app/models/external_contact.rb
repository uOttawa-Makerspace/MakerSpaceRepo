class ExternalContact < ApplicationRecord
  has_many :keys, as: :holder, dependent: :restrict_with_error
  has_many :key_transactions, as: :holder, dependent: :nullify

  scope :active, -> { where(deleted: false) }

  normalizes :email, with: ->(email) { email&.strip&.downcase }
  normalizes :first_name, :last_name, with: ->(name) { name&.strip }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :phone, format: { with: /\A[\d\-\+\(\)\s]*\z/ }, allow_blank: true

  def name
    "#{first_name} #{last_name}".strip
  end

  def soft_delete!
    # Refuse to soft delete if they currently hold keys
    if keys.any? { |k| k.status == "held" }
      false
    else
      update!(deleted: true)
    end
  end

  def self.find_or_create_by_details(first_name:, last_name:, email:, phone: nil)
    normalized = email.to_s.strip.downcase
    attempts = 0
    begin
      # Use unscoped so we can find and restore soft-deleted contacts if they return
      contact = unscoped.find_or_initialize_by(email: normalized)
      contact.first_name = first_name.to_s.strip
      contact.last_name  = last_name.to_s.strip
      contact.phone      = phone.presence
      contact.deleted    = false
      contact.save
      contact
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts <= 2
      unscoped.find_by(email: normalized)
    end
  end
end