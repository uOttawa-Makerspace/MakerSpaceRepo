module AvatarTestHelper
  extend self
  extend ActionDispatch::TestProcess

  def png_name; 'avatar.png' end
  def png; upload(png_name, 'image/png') end

  def stl_name; 'test.stl' end
  def stl; upload(stl_name, 'model/x.stl-binary') end

  private

  def upload(name, type)
    file_path = Rails.root.join('spec', 'support', 'assets', name)
    fixture_file_upload(file_path, type)
  end
end
