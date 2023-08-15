class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  has_many_attached :files, dependent: :destroy

  enum :status,
       %i[unknown inventory held lost waiting_for_approval],
       prefix: true

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
            },
            unless: :status_waiting_for_approval?

  validates :phone_number,
            :emergency_contact_phone_number,
            format: {
              with: /\A\d{10}\z/,
              message: "should be a 10-digit number"
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

  scope :waiting_for_approval, -> { where(status: :waiting_for_approval) }
  scope :approved, -> { where.not(status: :waiting_for_approval) }
end
