class Shift < ApplicationRecord
  belongs_to :user
  belongs_to :space

  before_save :create_update_shift
  before_destroy :delete_shift

  validates :start_datetime, presence: true
  validates :end_datetime, presence: true

  private

  def create_update_shift

  end

  def delete_shift

  end
end
