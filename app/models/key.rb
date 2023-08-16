class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  belongs_to :key_request, optional: true
  has_many :key_transactions, dependent: :destroy

  enum :status, %i[unknown inventory held lost], prefix: true
  enum :key_type, %i[regular submaster keycard], prefix: true

  validates :user,
            presence: {
              message: "A user is required if the key is held"
            },
            if: :status_held?
  validates :supervisor,
            presence: {
              message: "A supervisor is required if the key is held"
            },
            if: :status_held?
  validates :space, presence: { message: "A space is required" }

  validates :number,
            presence: {
              message: "A key number is required"
            },
            uniqueness: {
              message: "A key already has that number"
            }

  validates :phone_number,
            :emergency_contact_phone_number,
            format: {
              with: /\A\d{10}\z/,
              message: "should be in xxxxxxxxxx format"
            },
            unless: :status_inventory?

  validates :student_number,
            :emergency_contact,
            presence: {
              message: "student number and emergency contact is required"
            },
            unless: :status_inventory?

  validates :files,
            file_content_type: {
              allow: %w[application/pdf],
              if: -> { files.attached? }
            }
end
