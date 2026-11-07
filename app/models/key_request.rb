class KeyRequest < ApplicationRecord
  include DisplayUser
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  display_user_for :user, :supervisor

  enum :user_status, %i[student professor staff], prefix: true
  enum :status, %i[in_progress waiting_for_approval approved], prefix: true

  # The owner may change a request only while it is still being filled in.
  def editable_by_owner?
    status_in_progress?
  end

  # Only a request still being filled in can be submitted. A request already
  # waiting or approved is left as it is.
  def submit
    status_in_progress? && update(status: :waiting_for_approval)
  end

  NUMBER_OF_QUESTIONS = 14
  QUESTIONS = [
    "The university of Ottawa's Emergency number is the following:",
    "The nearest fire extinguisher is mounted in the following location:",
    "The building fire alarm system can be activated at the nearest fire alarm pull station located:",
    "All individuals must know the nearest primary and secondary escape routes from their room. An evacuation plan showing these escape routes from the building is in the following location:",
    "The nearest first aid kit is in the following location:",
    "The nearest designated first-aider is in the following location:",
    "A list of all designated first aiders is in the following location:",
    "Information concerning the Faculty's Health and Safety staff members can be found online. The Health, Safety and Risk Manager for theFaculty of Engineering is:",
    "The Office of Risk Management's Health and safety committee webpage lists the names of all committee members. My representative on the Office Functional Occupational Health and Safety Committee or the Laboratory Functional Occupational Health and Safety Committee is:",
    "The nearest emergency eyewash station is in the following location:",
    "The nearest safety shower is in the following location",
    "The nearest spill kit is in the following location:",
    "Personal Protective Equipment (i.e. respirator, face shield, cold gloves, blast shield, etc.) can be found in the following location:",
    "The following hazards, for which training is required, are present in the laboratory (i.e. laser, x-ray diffraction, high voltage, high pressure, flame photometer, NMR, high vacuum pump, etc.):"
  ]

  validates :user, presence: true
  validates :supervisor, presence: true
  validates :space, presence: true
  validates :user_status, presence: true

  validates :phone_number,
            :emergency_contact_phone_number,
            format: {
             # Got regex from here: https://stackoverflow.com/questions/16699007/regular-expression-to-match-standard-10-digit-phone-number
              with: /\A(\+\d{1,2}\s?)?\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}\z/,
              message: :invalid_phone
            }

  validates :student_number,
            :emergency_contact,
            presence: {
              message: :student_number_and_emergency_contact_required
            }

  validates :read_lab_rules,
            :read_policies,
            :read_agreement,
            acceptance: {
              accept: true,
              message: :rules_not_accepted
            },
            unless: :status_in_progress?

  (1..KeyRequest::NUMBER_OF_QUESTIONS).each do |i|
    validates "question_#{i}".to_sym,
              presence: {
                message: :question_required,
                question_number: i
              },
              unless: :status_in_progress?
  end
end