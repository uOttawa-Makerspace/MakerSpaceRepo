class RemoveKeyRequestFromKeys < ActiveRecord::Migration[7.0]
  def change
    remove_reference :keys, :key_request
  end
end
