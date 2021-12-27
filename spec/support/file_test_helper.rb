module FilesTestHelper
  extend self
  include ActionDispatch::TestProcess::FixtureFile

  def stl_name; 'test.stl' end
  def stl; upload(stl_name, 'model/x.stl-binary') end

  def png_name; 'test.png' end
  def png; upload(png_name, 'image/png') end

  def mp4_name; '1sec.mp4' end
  def mp4; upload(mp4_name, 'video/mp4') end

  def pdf_name; 'RepoFile1.pdf' end
  def pdf; upload(pdf_name, 'application/pdf') end

  private

  def upload(name, type)
    Rack::Test::UploadedFile.new("spec/support/assets/#{name}", type)
  end
end