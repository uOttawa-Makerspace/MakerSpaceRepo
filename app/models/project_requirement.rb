# frozen_string_literal: true

class ProjectRequirement < ApplicationRecord
  belongs_to :proficient_project, optional: true
  belongs_to :required_project, class_name: "ProficientProject", optional: true
  validates :proficient_project_id,
            uniqueness: {
              scope: :required_project_id
            }
  # Existing rows are only checked when their ends change, so an older row stays editable.
  validates :proficient_project, :required_project, presence: true, if: :ends_changed?
  validate :not_circular, if: :ends_changed?

  private

  def ends_changed?
    new_record? || will_save_change_to_proficient_project_id? || will_save_change_to_required_project_id?
  end

  # A project may not require itself, directly or through the projects it requires.
  def not_circular
    return if proficient_project_id.blank? || required_project_id.blank?

    errors.add(:required_project, :circular) if requires_transitively?(required_project_id, proficient_project_id)
  end

  def requires_transitively?(from_id, target_id)
    seen = Set.new
    queue = [from_id]
    while (id = queue.shift)
      return true if id == target_id
      next unless seen.add?(id)

      queue.concat(ProjectRequirement.where(proficient_project_id: id).pluck(:required_project_id).compact)
    end
    false
  end
end
