class WalkInSafetySheet < ApplicationRecord

  # how many checkboxes should be sent
  NUMBER_OF_AGREEMENTS = 6

  belongs_to :user
  belongs_to :space

  # This is how you validate a boolean
  validates :is_minor, inclusion: [true, false]

  # Adult info
  validates :participant_signature, presence: true, unless: :is_minor?
  validates :participant_telephone_at_home, presence: true, unless: :is_minor?

  # Minor info
  validates :guardian_signature, presence: true, if: :is_minor?
  validates :minor_participant_name, presence: true, if: :is_minor?
  validates :guardian_telephone_at_home, presence: true, if: :is_minor?
  validates :guardian_telephone_at_work, presence: true, if: :is_minor?

  # Emergency contact
  validates :emergency_contact_name, presence: true
  validates :emergency_contact_telephone, presence: true
end
