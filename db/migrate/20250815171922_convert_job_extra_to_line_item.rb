class ConvertJobExtraToLineItem < ActiveRecord::Migration[7.2]
  # Whoops we didn't move over job_order_extras
  def change
    JobOrderQuoteTypeExtra.find_each do |quote_extra|
      # Get the job order itself,
      job_order = quote_extra.job_order_quote.job_order
      # name of the extra fees
      job_type_extra = quote_extra.job_type_extra

      JobQuoteLineItem.create!(
        job_order: job_order,
        description: job_type_extra.name,
        price: quote_extra.price
      )
    end
  end
end
