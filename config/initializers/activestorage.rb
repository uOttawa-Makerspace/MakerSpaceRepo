Rails.application.config.after_initialize do
  ActiveStorage::Blob.class_eval do
    alias_method :upload_without_unfurling_original, :upload_without_unfurling

    def upload_without_unfurling(io)
      begin
        if io.extname == ".jpg" || io.extname == ".jpeg" || io.extname == ".png"
          ActiveStorage::Variation
            .wrap({ convert: "webp" })
            .transform(io) do |output|
              unfurl output, identify: identify
              upload_without_unfurling_original(output)
            end
        else
          upload_without_unfurling_original(io)
        end
      rescue StandardError
        upload_without_unfurling_original(io)
      end
    end
  end
end
