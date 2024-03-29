# frozen_string_literal: true

class VolunteerTask < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true
  has_many :volunteer_hours, dependent: :destroy
  has_many :volunteer_task_joins, dependent: :destroy
  has_many :require_trainings
  has_many :volunteer_task_requests, dependent: :destroy
  has_many :cc_moneys, dependent: :destroy
  has_many :photos, dependent: :destroy

  validate :validate_photos

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
