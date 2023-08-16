class KeyRequest < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true

  validates :user, presence: { message: "A user is required" }
  validates :supervisor, presence: { message: "A supervisor is required" }
  validates :space, presence: { message: "A space is required" }

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

  validates :files,
            file_content_type: {
              allow: %w[application/pdf],
              if: -> { files.attached? }
            }

  def get_approval_params
    {
      key_request_id: id,
      user_id: user_id,
      supervisor_id: supervisor_id,
      student_number: student_number,
      phone_number: phone_number,
      emergency_contact: emergency_contact,
      emergency_contact_relation: emergency_contact_relation,
      emergency_contact_phone_number: emergency_contact_phone_number
    }
  end
end
