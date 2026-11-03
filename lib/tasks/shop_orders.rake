# frozen_string_literal: true

namespace :shop_orders do
  desc "Re-run a failed stored order: rake shop_orders:reapply[ID] (the row id, or the provider ref such as the Shopify order id)"
  task :reapply, [:id] => :environment do |_task, args|
    key = args[:id].to_s
    abort "usage: rake shop_orders:reapply[ID]" if key.blank?

    order = ProcessedOrder.find_by(provider: ShopOrderApplier::PROVIDER, provider_ref: key) ||
            ProcessedOrder.find_by(id: key.match?(/\A\d{1,9}\z/) ? key : nil)
    abort "no stored order #{key}" unless order
    unless order.reapply!
      abort "order #{order.provider_ref} is #{order.reload.status}, only failed orders are re-run"
    end

    # A job that cannot be queued now is picked up by the stranded-order sweep.
    if ApplyProcessedOrderJob.perform_later(order.id)
      puts "order #{order.provider_ref} queued again"
    else
      puts "order #{order.provider_ref} reset to received; it could not be queued now and the sweep will queue it"
    end
  end
end
