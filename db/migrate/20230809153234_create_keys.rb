class CreateKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :keys do |t|
      t.references :user
      t.references :supervisor
      t.references :space

      t.string :number
      t.string :status

      t.timestamps
    end
  end
end
