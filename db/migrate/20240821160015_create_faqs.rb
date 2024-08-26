class CreateFaqs < ActiveRecord::Migration[7.0]
  def change
    create_table :faqs do |t|
      t.string :title_en
      t.string :title_fr
      t.text :body_en
      t.text :body_fr
      t.integer :order

      t.timestamps
    end
  end
end
