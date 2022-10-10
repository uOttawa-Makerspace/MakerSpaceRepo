# frozen_string_literal: true

class UpdateOldUsersRequiredFields < ActiveRecord::Migration[5.0]
  def change
    User.unscoped.where(name: nil).update_all(name: "anonymous")
    User.unscoped.where(gender: nil).update_all(gender: "unknown")
    User.unscoped.where(identity: nil).update_all(identity: "unknown")
  end
end
