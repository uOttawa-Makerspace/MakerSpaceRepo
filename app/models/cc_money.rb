# frozen_string_literal: true

class CcMoney < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :volunteer_task, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :order, optional: true
  belongs_to :discount_code, optional: true

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  def self.make_new_payment(user, cc)
    cc *= -1 if cc > 0
    cc_money = create(user: user, cc: cc)
    user.update_wallet
    cc_money
  end
end
