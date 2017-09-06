class ResetRole < ActiveRecord::Migration
  def up
    User.where(role: "admin").update_all(role: "regular_user")
    if user = User.find_by_email("kchuk030@uottawa.ca")
      user.update(role: "admin")
    end
    if user = User.find_by_email("psaha091@uottawa.ca")
      user.update(role: "admin")
    end
  end
end
