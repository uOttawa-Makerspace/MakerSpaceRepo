class CreateCategoryOptions < ActiveRecord::Migration
  def change
    create_table :category_options do |t|
      t.string :name

      t.timestamps null: false
    end
  end
end
