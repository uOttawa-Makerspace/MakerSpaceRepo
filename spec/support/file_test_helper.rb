module FilesTestHelper
  extend self
  include ActionDispatch::TestProcess::FixtureFile

  def stl_name
    "test.stl"
  end
  def stl
    upload(stl_name, "model/x.stl-binary")
  end

  def png_name
    "test.png"
  end
  def png
    upload(png_name, "image/png")
  end

  def mp4_name
    "1sec.mp4"
  end
  def mp4
    upload(mp4_name, "video/mp4")
  end

  def pdf_name
    "RepoFile1.pdf"
  end
  def pdf
    upload(pdf_name, "application/pdf")
  end

  # In-memory uploads whose type the server derives from content and name
  # (ActiveStorage sniffs with Marcel), used to prove the allowlists reject them.
  def zip_name
    "model.zip"
  end

  def zip
    in_memory(zip_name, "application/zip", "PK\x05\x06#{"\x00" * 18}".b)
  end

  def exe_name
    "setup.exe"
  end

  def exe
    in_memory(exe_name, "application/x-msdownload", "MZ#{"\x90" * 126}".b)
  end

  private

  def in_memory(name, type, bytes)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, true, original_filename: name)
  end

  def upload(name, type)
    Rack::Test::UploadedFile.new("spec/support/assets/#{name}", type)
  end
end
