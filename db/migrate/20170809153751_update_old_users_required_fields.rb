# frozen_string_literal: true

class UpdateOldUsersRequiredFields < ActiveRecord::Migration[5.0]
  def change
    User.where(name: nil).update_all(name: 'anonymous')
    User.where(gender: nil).update_all(gender: 'unknown')
    User.where(identity: nil).update_all(identity: 'unknown')
  end
end
