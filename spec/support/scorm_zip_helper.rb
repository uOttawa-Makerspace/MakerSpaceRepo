require 'zip'

# Helper module to create a zip file for learning module scorm testing. Zip with
# two files, one is the manifest and the other is an index
module ScormZipHelper
  extend self
  extend ActionDispatch::TestProcess

  def create_scorm_zip(entry_point = 'index.html', nested_dir: nil)
    path = Rails.root.join('tmp', 'test_scorm.zip')

    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry([nested_dir, 'imsmanifest.xml'].compact.join('/'))
      zip.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest>
          <resources>
            <resource identifier="res1" type="webcontent" adlcp:scormtype="sco" href="#{entry_point}"/>
          </resources>
        </manifest>
      XML

      zip.put_next_entry([nested_dir, entry_point].compact.join('/'))
      zip.write('<html><body>SCORM Content</body></html>')
    end

    Rack::Test::UploadedFile.new(path, 'application/zip')
  end
end
