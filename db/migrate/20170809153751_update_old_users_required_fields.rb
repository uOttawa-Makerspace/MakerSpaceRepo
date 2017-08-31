class UpdateOldUsersRequiredFields < ActiveRecord::Migration
  def change
    User.where(name: nil).update_all(name: "anonymous")
    User.where(gender: nil).update_all(gender: "unknown")
    User.where(identity: nil).update_all(identity: "unknown")
  end
end
