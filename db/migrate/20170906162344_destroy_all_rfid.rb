class DestroyAllRfid < ActiveRecord::Migration
  def up
    Rfid.destroy_all
  end
end
