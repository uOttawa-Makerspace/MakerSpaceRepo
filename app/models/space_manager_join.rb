class SpaceManagerJoin < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  validate :is_admin
  validates_uniqueness_of :user_id, scope: :space_id

  # The space managers as [name, id] options, each once, sorted by name ignoring case.
  def self.supervisor_options
    includes(:user).map { |join| [join.user.name, join.user.id] }.uniq.sort_by { |option| option[0].downcase }
  end

  private

  def is_admin
    errors.add(:base, :must_be_admin) if user.present? && !user.admin?
  end
end
