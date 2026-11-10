class KeyRequest < ApplicationRecord
  include DisplayUser
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  display_user_for :user, :supervisor

  enum :user_status, %i[student professor staff], prefix: true
  # New statuses are appended: the stored integers 0 to 2 must not change.
  enum :status, %i[in_progress waiting_for_approval approved denied], prefix: true

  MAX_DENIAL_REASON_LENGTH = 1000

  validates :denial_reason, length: { maximum: MAX_DENIAL_REASON_LENGTH }

  # The owner may change a request while it is being filled in, or after an admin denied it.
  def editable_by_owner?
    status_in_progress? || status_denied?
  end

  # Submits a request that is being filled in, or resubmits a denied one for approval. The denial
  # reason is cleared only when the resubmission is saved. A request already waiting or approved
  # is left as it is.
  def submit
    editable_by_owner? && update(status: :waiting_for_approval, denial_reason: nil)
  end

  # An admin's refusal of a waiting request, with the reason they typed (kept until resubmission).
  def deny(reason)
    update(status: :denied, denial_reason: reason.to_s.strip.presence)
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
            unless: :editable_by_owner?

  (1..KeyRequest::NUMBER_OF_QUESTIONS).each do |i|
    validates "question_#{i}".to_sym,
              presence: {
                message: :question_required,
                question_number: i
              },
              unless: :editable_by_owner?
  end
end