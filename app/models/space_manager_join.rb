class SpaceManagerJoin < ApplicationRecord
  belongs_to :user
  belongs_to :space

  validate :is_admin
  validates_uniqueness_of :user_id, scope: :space_id

  # The space managers as [name, id] options, each once, sorted by name ignoring case.
  def self.supervisor_options
    User.where(id: select(:user_id)).pluck(:name, :id).sort_by { |name, id| [name.downcase, id] }
  end

  private

  def is_admin
    errors.add(:base, :must_be_admin) if user.present? && !user.admin?
  end
end
