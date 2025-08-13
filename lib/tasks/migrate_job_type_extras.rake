namespace :data_migration do
  desc "Migrate JobTypeExtras and QuoteTypeExtras to JobOptions and QuoteOptions"
  task migrate_job_type_extras: :environment do
    puts "Starting JobTypeExtra -> JobOption migration"

    JobTypeExtra.find_each do |extra|
      # Create JobOption from JobTypeExtra
      job_option = JobOption.find_or_initialize_by(name: extra.name)
      job_option.description ||= extra.description
      job_option.fee ||= extra.price || 0
      job_option.need_files = false
      job_option.save!

      # Associate JobType
      if extra.job_type_id.present?
        JobOptionsType.find_or_create_by!(
          job_option_id: job_option.id,
          job_type_id: extra.job_type_id
        )
      end

      # Convert JobOrderQuoteTypeExtras to JobOrderQuoteOptions
      extra.job_order_quote_type_extras.find_each do |quote_extra|
        JobOrderQuoteOption.create!(
          job_option_id: job_option.id,
          job_order_quote_id: quote_extra.job_order_quote_id,
          amount: quote_extra.price
        )
      end

    rescue StandardError => e
      puts "Error migrating JobTypeExtra ##{extra.id}: #{e.class} - #{e.message}"
    end

    puts "Migration complete!"
  end
end
