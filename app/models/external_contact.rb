# app/models/external_contact.rb
class ExternalContact < ApplicationRecord
  has_many :keys, as: :holder, dependent: :restrict_with_error
  has_many :key_transactions, as: :holder, dependent: :nullify

  scope :active, -> { where(deleted: false) }

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :first_name, :last_name, with: ->(name) { name.strip }

  encrypts :email, deterministic: true
  encrypts :phone

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, email: true, uniqueness: true
  validates :phone, format: { with: /\A[\d\-\+\(\)\s]*\z/ }, allow_blank: true

  before_destroy :prevent_destroy_if_holding_keys

  def name
    "#{first_name} #{last_name}".strip
  end

  def self.find_or_create_by_details(first_name:, last_name:, email:, phone: nil)
    contact = create_or_find_by(email: email) do |c|
      c.first_name = first_name
      c.last_name  = last_name
      c.phone      = phone
    end
    contact.update(first_name: first_name, last_name: last_name, phone: phone.presence || contact.phone) if contact.persisted?
    contact
  end

  def soft_delete!
    return false if keys.exists?
    update!(deleted: true)
  end

  private

  def prevent_destroy_if_holding_keys
    if keys.exists?
      errors.add(:base, "Cannot delete a contact who currently holds a key")
      throw :abort
    end
  end
end