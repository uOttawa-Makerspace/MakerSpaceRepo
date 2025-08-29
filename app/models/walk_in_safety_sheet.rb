class WalkInSafetySheet < ApplicationRecord
  # how many checkboxes should be sent
  NUMBER_OF_AGREEMENTS = 6

  # Set supervisor information on initialization to simplify controller and view
  after_initialize :set_supervisor_information
  # Reset supervisor info, before commiting to database for first time
  before_create :set_supervisor_information
  # Prevent accidental modification after persistence
  attr_readonly :supervisor_names
  attr_readonly :supervisor_contacts

  belongs_to :user
  belongs_to :space

  # Only one sheet per space for each user
  validates :space, uniqueness: { scope: :user }

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

  # Space supervisors. This is stored as a comma-separated string in DB
  # Because supervisors might change over time.

  # convenience function to choose between supervisor on file or the current
  # space supervisor. Returns [['name', 'phone'], ['name', 'phone']]
  def supervisor_information
    names = supervisor_names.split(',')
    contacts = supervisor_contacts.split(',')
    names.zip contacts
  end

  private

  def set_supervisor_information
    return if persisted? # only new records
    # Hardcode brunsfield
    self.space ||= Space.find_by(name: "Brunsfield Centre")
    return unless space # space has to be set
    infos = space.space_managers.pluck(:name, :email) # Hardcoded brunsfield centre
    self.supervisor_names ||= infos.map(&:first).join(',')
    self.supervisor_contacts ||= infos.map(&:last).join(',')
  end
end
