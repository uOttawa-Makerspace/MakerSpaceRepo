class KeyRequest < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  has_one :staff_certification, through: :user

  enum :user_status, %i[student professor staff], prefix: true

  validates :user, presence: { message: "A user is required" }
  validates :supervisor, presence: { message: "A supervisor is required" }
  validates :space, presence: { message: "A space is required" }
  validates :user_status, presence: { message: "A user status is required" }

  validates :phone_number,
            :emergency_contact_phone_number,
            format: {
              with: /\A\d{10}\z/,
              message: "should be in xxxxxxxxxx format"
            }

  validates :student_number,
            :emergency_contact,
            presence: {
              message: "student number and emergency contact is required"
            }
end
