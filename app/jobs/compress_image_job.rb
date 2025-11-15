# frozen_string_literal: true

class CompressImageJob < ApplicationJob
  queue_as :default
  
  COMPRESSIBLE_FORMATS = %w[image/jpeg image/png].freeze
  CONVERTIBLE_FORMATS = %w[image/bmp].freeze  # Convert BMP to JPEG

  def perform(photo_id)
    photo = Photo.find(photo_id)
    return unless photo.image.attached?

    content_type = photo.image.blob.content_type
    
    # Skip unsupported formats
    return unless COMPRESSIBLE_FORMATS.include?(content_type) || 
                  CONVERTIBLE_FORMATS.include?(content_type)

    original_size = photo.image.blob.byte_size

    photo.image.blob.open do |file|
      processor = ImageProcessing::Vips
        .source(file)
        .resize_to_limit(2000, 2000)
      
      # BMP → JPEG conversion with compression
      if content_type == 'image/bmp'
        compressed = processor
          .convert('jpg')
          .saver(quality: 85, strip: true)
          .call
        new_content_type = 'image/jpeg'
      else
        compressed = processor
          .saver(quality: 85, strip: true)
          .call
        new_content_type = content_type
      end
      
      new_size = File.size(compressed.path)
      
      # Only attach if smaller
      if new_size < original_size
        photo.image.attach(
          io: File.open(compressed.path),
          filename: photo.image.blob.filename.to_s.gsub(/\.bmp$/i, '.jpg'),
          content_type: new_content_type
        )
        
        savings = ((1 - new_size.to_f / original_size) * 100).round(2)
        Rails.logger.info "Photo ##{photo_id}: #{format_bytes(original_size)} → #{format_bytes(new_size)} (#{savings}% saved)"
      else
        Rails.logger.info "Photo ##{photo_id}: already optimized"
      end
    end
  rescue StandardError => e
    Rails.logger.error "Photo ##{photo_id} failed: #{e.message}"
  end
  
  private
  
  def format_bytes(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(2)} KB"
    else
      "#{(bytes / 1024.0 / 1024.0).round(2)} MB"
    end
  end
end