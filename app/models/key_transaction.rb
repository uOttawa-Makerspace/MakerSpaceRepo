class KeyTransaction < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :holder, polymorphic: true, optional: true
  belongs_to :key, optional: true

  def user
    holder if holder_type == "User"
  end

  def user_id
    holder_id if holder_type == "User"
  end

  def user_id=(id)
    self.holder = id.present? ? User.find_by(id: id) : nil
  end

  validates :holder, presence: true
  validates :key, presence: true
  validates :deposit_amount, presence: true

  scope :returned, -> { where.not(return_date: nil) }
  scope :not_returned, -> { where(return_date: nil) }
  scope :awaiting_deposit_return,
        -> { where.not(return_date: nil).where(deposit_return_date: nil) }

  def assignee_name
    holder&.name || "Unassigned"
  end

  def assignee_email
    holder.try(:email)
  end
end