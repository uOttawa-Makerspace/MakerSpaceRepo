namespace :active_storage do
  task migrate: :environment do
    Rails.application.eager_load!
    models = ActiveRecord::Base.descendants.reject(&:abstract_class?)
    @bucket_name = Rails.application.credentials[Rails.env.to_sym][:aws][:bucket_name]
    @region = Rails.application.credentials[Rails.env.to_sym][:aws][:region]
    models.each do |model|
      attachments = model.column_names.map do |c|
        if c =~ /(.+)_file_name$/
          $1
        end
      end.compact

      if attachments.blank?
        next
      end

      attachments.each do |attachment|
        migrate_data(attachment,model)
      end
    end
  end

  private

    def migrate_data(attachment, model)
      model.where.not("#{attachment}_file_name": nil).find_each do |instance|

        content_type = instance.send("#{attachment}_content_type")
        filename = instance.send("#{attachment}_file_name")

        next if filename.blank?

        klass = instance.class.table_name
        id = instance.id
        id_partition = ("%09d".freeze % id).scan(/\d{3}/).join("/".freeze)

        if klass.to_s == 'photos'
          url = "https://#{@bucket_name}.s3-#{@region}.amazonaws.com/repo_images/#{id}/#{filename}"
        elsif klass.to_s == 'repo_files'
          url = "https://#{@bucket_name}.s3-#{@region}.amazonaws.com/repo_files/#{id}/#{filename}"
        else
          url = "https://#{@bucket_name}.s3-#{@region}.amazonaws.com/#{klass}/#{attachment.pluralize}/#{id_partition}/original/#{filename}"
        end

        next if return_response_from_url(url) != "200"

        puts url

        instance.send(attachment.to_sym).attach(
            io: open(url),
            filename: filename,
            content_type: content_type
        )
      end
    end

    def return_response_from_url(url)
      url = url.gsub(" ", "_")
      url = URI.encode(url)
      url = URI.parse(url)
      req = Net::HTTP.new(url.host, url.port)
      req.use_ssl = true
      res = req.request_head(url.path)
      res.code
    end

end