module AvatarTestHelper
  extend self
  extend ActionDispatch::TestProcess

  def png_name
    "avatar.png"
  end
  def png
    upload(png_name, "image/png")
  end

  def stl_name
    "test.stl"
  end
  def stl
    upload(stl_name, "model/x.stl-binary")
  end

  private

  def upload(name, type)
    Rack::Test::UploadedFile.new("spec/support/assets/#{name}", type)
  end
end
