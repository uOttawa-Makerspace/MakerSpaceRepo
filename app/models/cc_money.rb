class CcMoney < ActiveRecord::Base
  belongs_to :user
  belongs_to :volunteer_task
  belongs_to :proficient_project

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    self.create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  def self.create_cc_money_from_order(proficient_project_id, user_id, cc)
    cc *= -1 if cc >= 0
    self.create(proficient_project_id: proficient_project_id, user_id: user_id, cc: cc)
  end
end
