# frozen_string_literal: true

namespace :shop_orders do
  desc "Re-run a failed stored order: rake shop_orders:reapply[ID] (the row id, or the provider ref such as the Shopify order id)"
  task :reapply, [:id] => :environment do |_task, args|
    key = args[:id].to_s
    abort "usage: rake shop_orders:reapply[ID]" if key.blank?

    order = ProcessedOrder.find_by(provider: ShopOrderApplier::PROVIDER, provider_ref: key) ||
            ProcessedOrder.find_by(id: key.match?(/\A\d{1,9}\z/) ? key : nil)
    abort "no stored order #{key}" unless order
    abort "order #{order.provider_ref} is #{order.status}, only failed orders are re-run" unless order.reapply!

    ApplyProcessedOrderJob.perform_later(order.id)
    puts "order #{order.provider_ref} queued again"
  end
end
