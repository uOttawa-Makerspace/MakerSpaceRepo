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

    # Due now: handed to the queue here, or by the recurring dispatcher if that fails.
    if ProcessedOrder.dispatch_due(id: order.id).any?
      puts "order #{order.provider_ref} queued again"
    else
      puts "order #{order.provider_ref} reset to received; the dispatcher will queue it"
    end
  end

  desc "List applied orders that had a part refused (such as a payment for a membership that was not pending): rake shop_orders:refused"
  task refused: :environment do
    orders = ProcessedOrder.refused.order(:applied_at)
    puts "no refused orders" if orders.empty?
    orders.each { |o| puts "#{o.provider_ref} (#{o.order_name}) applied #{o.applied_at&.iso8601}: #{o.last_error}" }
  end
end
