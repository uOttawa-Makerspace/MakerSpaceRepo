# require 'rails_helper'
#
# RSpec.describe CustomWebhooksController, type: :controller do
#   describe "POST /orders_paid" do
#     context 'webhook from shopify when user pays an order' do
#       it 'should update discount code as used (usage count = 1)' do
#         discount_code = create(:discount_code)
#         post :orders_paid, params: { 'discount_codes' => [ {'code' => discount_code.code.to_s } ] }
#         expect(DiscountCode.find_by(id: discount_code.id).usage_count).to eq(1)
#       end
#     end
#   end
# end
#
