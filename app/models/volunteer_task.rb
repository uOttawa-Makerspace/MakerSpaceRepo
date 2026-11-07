# frozen_string_literal: true

class VolunteerTask < ApplicationRecord
  class EditRefused < StandardError; end

  belongs_to :user, optional: true
  belongs_to :space, optional: true
  has_many :volunteer_hours, dependent: :destroy
  has_many :volunteer_task_joins, dependent: :destroy
  has_many :require_trainings, dependent: :destroy
  has_many :volunteer_task_requests, dependent: :destroy
  has_many :cc_moneys, dependent: :destroy
  has_many :photos, dependent: :destroy

  # Hours and CC already awarded for a task are kept: a task that has awarded either cannot be
  # deleted. The check runs before anything is destroyed (prepend), so no hours, joins or
  # requests are taken along.
  before_destroy :refuse_deletion_while_awarded, prepend: true

  validate :validate_photos
  # The task forms save in the :task_form context: a task's hours must be more than 0 when it is
  # created or edited there. Other updates (completing a task) and stored tasks are not checked.
  validates :hours, numericality: { greater_than: 0 }, on: %i[create task_form]

  # Awarded means: an approved volunteer hour row, or any CC money row, belongs to the task.
  def awarded?
    volunteer_hours.approved.exists? || cc_moneys.exists?
  end

  # Applies a whole task form (a new task or an edit) as one unit: the task's attributes, its required
  # trainings and its joins. Any step that fails undoes every step, leaves the reason in errors and
  # returns false. `joins` takes :add_staff, :add_volunteers, :remove_staff and :remove_volunteers
  # (lists of user ids).
  def update_from_form(attributes, certification_ids: [], joins: {})
    transaction do
      assign_attributes(attributes)
      save!(context: :task_form)
      replace_certifications(certification_ids)
      add_joins(joins[:add_staff], "staff", staff: true)
      add_joins(joins[:add_volunteers], "volunteer", staff: false)
      Array(joins[:remove_staff]).each { |user_id| remove_staff(user_id) }
      Array(joins[:remove_volunteers]).each { |user_id| remove_join(user_id, "volunteer") }
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record.equal?(self)
    false
  rescue EditRefused => e
    errors.add(:base, e.message)
    false
  end

  # Removes one user from the task on its own (the task page's remove forms, or a user leaving):
  # the same removal as the edit form, with the same creator handover. Returns false and leaves the
  # reason in errors when the user is not on the task or is the creator with nobody to take over.
  def remove_user(user_id)
    transaction { remove_staff(user_id, "user") }
    true
  rescue EditRefused => e
    errors.add(:base, e.message)
    false
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

  def refuse!(message)
    raise EditRefused, message
  end

  def replace_certifications(certification_ids)
    ids = Array(certification_ids).compact_blank
    refuse!("A required training does not exist.") unless Training.where(id: ids).count == ids.uniq.size
    delete_all_certifications
    create_certifications(ids)
  end

  def add_joins(user_ids, label, staff:)
    Array(user_ids).each do |user_id|
      user = User.find_by(id: user_id)
      refuse!("The #{label} to add could not be found.") unless user
      volunteer_task_joins.create!(user: user, user_type: staff ? user.role.capitalize : "Volunteer", active: true)
    end
  end

  # A removed user's joins are kept as history and marked inactive.
  def remove_join(user_id, label)
    joins = volunteer_task_joins.active.where(user_id: user_id)
    refuse!("The #{label} to remove is not on this task.") if joins.empty?
    joins.update_all(active: false, updated_at: Time.current)
  end

  # The task's creator can only leave when another joined user can take over as creator.
  def remove_staff(user_id, label = "staff")
    if self.user_id == user_id.to_i
      successor = volunteer_task_joins.active.where.not(user_id: user_id).order(:id).first
      refuse!("There must be at least one staff member assigned to this task.") unless successor
      update!(user_id: successor.user_id)
    end
    remove_join(user_id, label)
  end

  def refuse_deletion_while_awarded
    return unless awarded?

    errors.add(:base, "This task has approved hours or CC awarded and cannot be deleted.")
    throw :abort
  end

  def validate_photos
    errors.add(:photos, " can't exceed 5 photos") if photos.count > 5
  end
end
