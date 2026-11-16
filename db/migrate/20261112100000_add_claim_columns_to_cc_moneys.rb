# Unclaimed CC Money keeps the address of the purchase and a claim-link generation. Both are additive: the new
# columns do not change any existing row (the address stays empty and the generation starts at 0), and nothing is
# removed. A resend raises the generation so earlier links stop working. down drops the two columns only.
class AddClaimColumnsToCcMoneys < ActiveRecord::Migration[8.1]
  def change
    add_column :cc_moneys, :purchaser_email, :string
    add_column :cc_moneys, :claim_token_generation, :integer, default: 0, null: false
  end
end
