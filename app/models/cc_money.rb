class CcMoney < ApplicationRecord
  belongs_to :user
  belongs_to :volunteer_task

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    self.create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end
end
