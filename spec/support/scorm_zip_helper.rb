require 'zip'

# Helper module to create a zip file for learning module scorm testing. Zip with
# two files, one is the manifest and the other is an index
module ScormZipHelper
  def create_scorm_zip(entry_point: 'index.html')
    path = Rails.root.join('tmp', 'test_scorm.zip')

    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('imsmanifest.xml')
      zip.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest>
          <resources>
            <resource identifier="res1" type="webcontent" adlcp:scormtype="sco" href="#{entry_point}"/>
          </resources>
        </manifest>
      XML

      zip.put_next_entry(entry_point)
      zip.write('<html><body>SCORM Content</body></html>')
    end

    Rack::Test::UploadedFile.new(path, 'application/zip')
  end
end
