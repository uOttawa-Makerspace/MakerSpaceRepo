class UpdatingIdentityOfOldUsers < ActiveRecord::Migration
  def change
    User.where("created_at < ?", 1.month.ago).where(identity: nil).update_all(identity: "unknown")
  end
end
