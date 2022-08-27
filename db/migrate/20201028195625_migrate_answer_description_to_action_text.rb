class MigrateAnswerDescriptionToActionText < ActiveRecord::Migration[6.0]
  include ActionView::Helpers::TextHelper
  def change
    rename_column :answers, :description, :description_old
    Answer.all.each do |answer|
      answer.update_attribute(
        :description,
        simple_format(answer.description_old)
      )
    end
    remove_column :answers, :description_old
  end
end
