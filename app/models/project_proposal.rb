class ProjectProposal < ActiveRecord::Base
  has_many   :categories,     dependent: :destroy
  has_one    :user,  -> {where(role: "regular_user")}
  has_one    :user,  -> {where(role: "admin")}
end
