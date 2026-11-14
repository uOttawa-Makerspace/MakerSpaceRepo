class SpaceManagerJoin < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  validate :is_admin
  validates_uniqueness_of :user_id, scope: :space_id

  # The space managers as [name, id] options, each once, sorted by name ignoring case. A row with no user is left out.
  def self.supervisor_options
    User.where(id: select(:user_id)).pluck(:name, :id).sort_by { |name, _id| name.downcase }
  end

  private

  def is_admin
    errors.add(:base, :must_be_admin) if user.present? && !user.admin?
  end
end
