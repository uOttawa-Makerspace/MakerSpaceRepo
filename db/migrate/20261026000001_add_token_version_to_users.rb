# D-I01: JWTs carry the user's token_version as `ver`; bumping it (password
# change/reset) revokes every token issued before. Additive and reversible;
# tokens minted before this deploy carry no `ver` and count as version 0.
class AddTokenVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :token_version, :integer, null: false, default: 0
  end
end
