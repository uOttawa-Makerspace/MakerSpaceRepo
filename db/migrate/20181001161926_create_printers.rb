class CreatePrinters < ActiveRecord::Migration
  def change
    create_table :printers do |t|

      t.timestamps null: false
    end
  end
end
