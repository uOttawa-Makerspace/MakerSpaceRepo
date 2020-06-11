class CcMoney < ActiveRecord::Base
  belongs_to :user
  belongs_to :volunteer_task
  belongs_to :proficient_project
  belongs_to :order_item
  belongs_to :discount_code

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    self.create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  def self.make_new_payment(user, cc)
    cc *= -1 if cc > 0
    cc_money = self.create(user: user, cc: cc)
    user.update_wallet
    cc_money
  end

end
