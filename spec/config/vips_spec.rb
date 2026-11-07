# frozen_string_literal: true

require "rails_helper"

# libvips decodes user uploads; its untrusted loaders (SVG, PDF, ImageMagick and the like) are switched off at boot
# in config/initializers/vips.rb.
RSpec.describe "libvips untrusted loaders" do
  let(:svg) { '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>' }

  it "refuses an untrusted loader" do
    expect { Vips::Image.new_from_buffer(svg, "") }.to raise_error(Vips::Error)
  end

  it "would load the same SVG with blocking off, so the refusal comes from the setting" do
    Vips.block_untrusted(false)
    begin
      expect(Vips::Image.new_from_buffer(svg, "").width).to eq(10)
    ensure
      load Rails.root.join("config/initializers/vips.rb")
    end
  end

  {
    "a PNG" => -> { Rack::Test::UploadedFile.new("spec/support/assets/test.png", "image/png") },
    "a JPEG" => lambda {
      Rack::Test::UploadedFile.new(StringIO.new(Vips::Image.black(300, 200).write_to_buffer(".jpg")), "image/jpeg",
                                   original_filename: "photo.jpg")
    },
    "a GIF" => lambda {
      Rack::Test::UploadedFile.new(StringIO.new(Vips::Image.black(300, 200).write_to_buffer(".gif")), "image/gif",
                                   original_filename: "photo.gif")
    }
  }.each do |name, upload|
    it "still makes the photo variants of #{name}" do
      photo = create(:photo)
      photo.image.attach(upload.call)
      %i[explore photo_slide photo_slide_first repo_display_wrapper].each do |variant|
        processed = photo.image.variant(variant).processed
        expect(processed.image.blob).to be_present
      end
    end
  end

  # Avatars and job order images are analysed when stored; the plain formats still get their dimensions.
  %w[png jpg webp gif].each do |format|
    it "reads the dimensions of a #{format} image" do
      data = Vips::Image.black(300, 200).write_to_buffer(".#{format}")
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: "image.#{format}")
      blob.analyze
      expect(blob.metadata).to include("width" => 300, "height" => 200)
    end
  end

  # Files only stored and served (SVG and PDF in job orders, project files) get no dimensions when analysed, and
  # are not otherwise touched by libvips.
  {
    "an SVG" => ["logo.svg", "image/svg+xml"],
    "a PDF" => ["RepoFile1.pdf", "application/pdf"]
  }.each do |name, (filename, type)|
    it "stores and analyses #{name} without error" do
      io = filename.end_with?(".svg") ? StringIO.new(svg) : File.open(Rails.root.join("spec/support/assets", filename))
      blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: type)
      expect { blob.analyze }.not_to raise_error
      expect(blob.download).to be_present
    end
  end
end
