class UpdateShareType < ActiveRecord::Migration
  def change
    Repository.where(share_type: nil).update_all(share_type: "public")
  end
end
