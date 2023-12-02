class SpaceManagerJoin < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  validate :is_admin
  validates_uniqueness_of :user_id, scope: :space_id

  private

  def is_admin
    errors.add(:base, "User must be an admin") if user.present? && !user.admin?
  end
end
