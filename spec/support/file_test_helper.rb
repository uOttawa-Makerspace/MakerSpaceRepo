module FilesTestHelper
  extend self
  extend ActionDispatch::TestProcess

  def stl_name; 'test.stl' end
  def stl; upload(stl_name, 'model/x.stl-binary') end

  def png_name; 'test.png' end
  def png; upload(png_name, 'image/png') end

  def mp4_name; '1sec.mp4' end
  def mp4; upload(mp4_name, 'video/mp4') end

  private

  def upload(name, type)
    file_path = Rails.root.join('spec', 'support', 'assets', name)
    fixture_file_upload(file_path, type)
  end
end