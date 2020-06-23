namespace :organizations do
  task migrate_to_active_storage: :environment do
    def perform
      models = ActiveRecord::Base.descendants.reject(&:abstract_class?)

      models.each do |model|
        attachments = model.column_names.map do |c|
          if c =~ /(.+)_file_name$/
            $1
          end
        end.compact

        attachments.each do |attachment|
          migrate_data(attachment,model)
        end
      end
    end

    private

    def migrate_data(attachment,model)
      model.where.not("#{attachment}_file_name": nil).find_each do |instance|
        bucket = ENV['AWS_BUCKET']
        name = instance.send("#{attachment}_file_name")
        content_type = instance.send("#{attachment}_content_type")
        id = instance.id

        url = "https://s3.amazonaws.com/#{bucket}/uploads/#{attachment.pluralize}/#{id}/original/#{name}"

        instance.send(attachment.to_sym).attach(
            io: open(url),
            filename: name,
            content_type: content_type
        )
      end
    end
  end
end