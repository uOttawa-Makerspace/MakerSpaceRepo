class Training < ActiveRecord::Base
  belongs_to :user

  validates :user, presence: true
  validates :name, presence: true
  validate :is_admin

  def is_admin
    errors.add(:string, "user must be admin") if self.user.role != "admin"
  end

end
