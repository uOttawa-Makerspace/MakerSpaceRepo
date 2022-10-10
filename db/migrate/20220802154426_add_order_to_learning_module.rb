class AddOrderToLearningModule < ActiveRecord::Migration[6.1]
  def change
    add_column :learning_modules, :order, :integer
    LearningModule.all.each_with_index { |lm, i| lm.update(order: i) }
  end
end
