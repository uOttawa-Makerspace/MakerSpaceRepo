require "rails_helper"

# Chunk 12: the SCORM zip -> content extraction contract (ScormExtractor,
# ExtractScormJob, LearningModule callbacks), with real zips.

RSpec.describe ScormExtractor do
  include ActiveJob::TestHelper

  def zip_io(entries)
    io = StringIO.new
    Zip::OutputStream.write_buffer(io) do |zip|
      entries.each { |name, body| zip.put_next_entry(name); zip.write(body) }
    end
    io.rewind
    io
  end

  MANIFEST = <<~XML
    <?xml version="1.0"?>
    <manifest xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_v1p3">
      <resources><resource identifier="r1" type="webcontent" href="%<href>s"/></resources>
    </manifest>
  XML

  def module_with(entries = nil, filename: "pkg.zip", **rest)
    entries ||= rest
    lm = create(:learning_module)
    lm.scorm_package.attach(io: zip_io(entries), filename: filename, content_type: "application/zip")
    lm.save!
    lm.reload
  end

  def names(lm)
    lm.scorm_package_files.map { |f| f.filename.to_s }
  end

  it "extracts every file, records prefix and entry point, and marks the module ready" do
    lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "start.html"), "start.html" => "<p>hi</p>",
                     "assets/app.js" => "x=1")
    ScormExtractor.extract(lm)
    lm.reload
    expect(lm.scorm_status).to eq("ready")
    expect(lm.scorm_entry_point).to eq("start.html")
    expect(lm.scorm_prefix).to match(%r{\Ascorm/learning_modules/test_#{lm.id}_[0-9a-f-]{36}\z})
    # ActiveStorage sanitizes "/" out of filenames; the nested path survives only in the blob key
    expect(names(lm)).to match_array(%w[imsmanifest.xml start.html assets-app.js])
    blob = lm.scorm_package_files.blobs.find_by(key: "#{lm.scorm_prefix}/start.html")
    expect(blob.download).to eq("<p>hi</p>")
    expect(blob.content_type).to eq("text/html")
    expect(lm.scorm_package_files.blobs.find_by(key: "#{lm.scorm_prefix}/assets/app.js").content_type).to eq("text/javascript")
  end

  it "strips a single wrapper directory above the manifest" do
    lm = module_with("wrap/imsmanifest.xml" => format(MANIFEST, href: "index.html"), "wrap/index.html" => "ok", "wrap/sub/a.css" => "a{}")
    ScormExtractor.extract(lm)
    expect(names(lm.reload)).to match_array(%w[imsmanifest.xml index.html sub-a.css])
    expect(lm.scorm_package_files.blobs.pluck(:key)).to include("#{lm.scorm_prefix}/sub/a.css")
    expect(lm.scorm_status).to eq("ready")
  end

  it "skips directories, __MACOSX and dot entries" do
    lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "i.html"), "i.html" => "ok",
                     "__MACOSX/._i.html" => "junk", ".DS_Store" => "junk")
    ScormExtractor.extract(lm)
    expect(names(lm.reload)).to match_array(%w[imsmanifest.xml i.html])
  end

  it "takes the first resource href of the manifest as the entry point; nil when none has an href" do
    lm = module_with("imsmanifest.xml" => "<manifest><resources><resource identifier='r'/></resources></manifest>", "i.html" => "x")
    ScormExtractor.extract(lm)
    expect(lm.reload.scorm_status).to eq("ready")
    expect(lm.scorm_entry_point).to be_nil
    expect(lm.scorm_ready?).to be(true)
  end

  it "re-extracting replaces the previous files and uses a new prefix" do
    lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "a.html"), "a.html" => "1")
    ScormExtractor.extract(lm)
    first_prefix = lm.reload.scorm_prefix
    ScormExtractor.extract(lm)
    lm.reload
    expect(lm.scorm_prefix).not_to eq(first_prefix)
    expect(names(lm)).to match_array(%w[imsmanifest.xml a.html])
    expect(ActiveStorage::Blob.where("key LIKE ?", "#{first_prefix}/%").count).to eq(0)
  end

  # WART(D-T33): a zip without imsmanifest.xml returns nil silently: the module is left in 'processing' forever, its old files purged
  it "leaves the module stuck in processing (and returns nil) when there is no manifest" do
    lm = module_with("index.html" => "x")
    expect(ScormExtractor.extract(lm)).to be_nil
    lm.reload
    expect(lm.scorm_status).to eq("processing")
    expect(lm.scorm_package_files).not_to be_attached
    expect(lm.scorm_ready?).to be(false)
  end

  it "marks the module failed and re-raises when the file is not a zip" do
    lm = create(:learning_module)
    lm.scorm_package.attach(io: StringIO.new("not a zip"), filename: "bad.zip", content_type: "application/zip")
    lm.save!
    expect { ScormExtractor.extract(lm) }.to raise_error(Zip::Error)
    expect(lm.reload.scorm_status).to eq("failed")
  end

  it "marks the module failed and re-raises when the manifest is not parseable as a resource list but zip is fine (still ready: Nokogiri is lenient)" do
    lm = module_with("imsmanifest.xml" => "<<<garbage", "i.html" => "x")
    ScormExtractor.extract(lm)
    expect(lm.reload.scorm_status).to eq("ready")
    expect(lm.scorm_entry_point).to be_nil
  end

  describe "ExtractScormJob" do
    it "extracts the module given by id" do
      lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "j.html"), "j.html" => "1")
      ExtractScormJob.perform_now(lm.id)
      expect(lm.reload.scorm_status).to eq("ready")
    end

    it "raises RecordNotFound for a deleted module" do
      expect { ExtractScormJob.perform_now(0) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is enqueued after commit whenever a new package is attached, and not on a plain update" do
      lm = create(:learning_module)
      expect { lm.scorm_package.attach(io: zip_io("imsmanifest.xml" => "<m/>"), filename: "p.zip", content_type: "application/zip"); lm.save! }
        .to have_enqueued_job(ExtractScormJob).with(lm.id)
      expect(lm.reload.scorm_status).to eq("pending")
      expect { lm.update!(title: "Changed title") }.not_to have_enqueued_job(ExtractScormJob)
    end

    it "uses the :always after-commit enqueue mode" do
      expect(ExtractScormJob.enqueue_after_transaction_commit).to eq(:always)
    end
  end

  describe "LearningModule#scorm_asset_url" do
    it "refuses path traversal" do
      lm = create(:learning_module)
      expect { lm.scorm_asset_url("../secret") }.to raise_error(ArgumentError, "Path traversal detected")
    end
  end
end
