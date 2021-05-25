class AddCommentsBoxToPrintOrdeers < ActiveRecord::Migration[6.0]
  def change
    add_column :print_orders, :comments_box, :string
  end
end
