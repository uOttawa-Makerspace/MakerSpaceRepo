class CreatePrinterIssues < ActiveRecord::Migration[7.0]
  def change
    create_table :printer_issues do |t|
      t.references :printer, null: false, foreign_key: true
      t.string :summary, null: false
      t.string :description
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
