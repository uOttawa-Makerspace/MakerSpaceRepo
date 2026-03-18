class AddPositionToPhotos < ActiveRecord::Migration[7.2]
  def change
    add_column :photos, :position, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        # Backfill existing photos with sequential positions
        Repository.find_each do |repo|
          repo.photos.unscoped.where(repository_id: repo.id)
              .order(:created_at)
              .each_with_index do |photo, idx|
            photo.update_column(:position, idx)
          end
        end
      end
    end
  end
end
