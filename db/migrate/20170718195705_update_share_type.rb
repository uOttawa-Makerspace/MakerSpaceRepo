# frozen_string_literal: true

class UpdateShareType < ActiveRecord::Migration[5.0]
  def change
    Repository.where(share_type: nil).update_all(share_type: 'public')
  end
end
