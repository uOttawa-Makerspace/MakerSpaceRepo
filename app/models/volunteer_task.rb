# frozen_string_literal: true

class VolunteerTask < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true
  has_many :volunteer_hours, dependent: :destroy
  has_many :volunteer_task_joins, dependent: :destroy
  has_many :require_trainings, dependent: :destroy
  has_many :volunteer_task_requests, dependent: :destroy
  has_many :cc_moneys, dependent: :destroy
  has_many :photos, dependent: :destroy

  validate :validate_photos
  # The task forms save in the :task_form context: a task's hours must be more than 0 when it is
  # created or edited there. Other updates (completing a task) and stored tasks are not checked.
  validates :hours, numericality: { greater_than: 0 }, on: %i[create task_form]

  # Sets the attributes and saves them from a task form (see the validations above).
  def save_from_form(attributes)
    assign_attributes(attributes)
    save(context: :task_form)
  end

  def delete_all_certifications
    require_trainings.destroy_all
  end

  def create_certifications(certification_ids)
    certification_ids.each do |certification_id|
      require_trainings.create(training_id: certification_id)
    end
  end

  private

  def validate_photos
    errors.add(:photos, " can't exceed 5 photos") if photos.count > 5
  end
end
