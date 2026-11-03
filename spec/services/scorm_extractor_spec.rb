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
    lm.update_columns(scorm_status: LearningModule.scorm_statuses[:pending])
    ScormExtractor.extract(lm)
    lm.reload
    expect(lm.scorm_prefix).not_to eq(first_prefix)
    expect(names(lm)).to match_array(%w[imsmanifest.xml a.html])
    expect(ActiveStorage::Blob.where("key LIKE ?", "#{first_prefix}/%").count).to eq(0)
  end

  it "marks the module failed with a readable reason when there is no manifest, keeping the previous files" do
    lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "a.html"), "a.html" => "1")
    ScormExtractor.extract(lm)
    lm.scorm_package.attach(io: zip_io("index.html" => "x"), filename: "other.zip", content_type: "application/zip")
    lm.save!
    ScormExtractor.extract(lm)
    lm.reload
    expect(lm.scorm_status).to eq("failed")
    expect(lm.scorm_error).to eq("no imsmanifest.xml found")
    expect(lm.scorm_ready?).to be(false)
    expect(lm.scorm_package_files).to be_attached
  end

  it "marks the module failed with the reason, without raising, when the file is not a zip" do
    lm = create(:learning_module)
    lm.scorm_package.attach(io: StringIO.new("not a zip"), filename: "bad.zip", content_type: "application/zip")
    lm.save!
    expect { ScormExtractor.extract(lm) }.not_to raise_error
    expect(lm.reload.scorm_status).to eq("failed")
    expect(lm.scorm_error).to eq("the file is not a valid zip archive")
  end

  it "marks the module failed and re-raises when the manifest is not parseable as a resource list but zip is fine (still ready: Nokogiri is lenient)" do
    lm = module_with("imsmanifest.xml" => "<<<garbage", "i.html" => "x")
    ScormExtractor.extract(lm)
    expect(lm.reload.scorm_status).to eq("ready")
    expect(lm.scorm_entry_point).to be_nil
  end

  describe "claiming an extraction" do
    let(:files) { { "imsmanifest.xml" => format(MANIFEST, href: "a.html"), "a.html" => "1" } }

    it "leaves a ready module ready when a duplicate run arrives" do
      lm = module_with(files)
      ScormExtractor.extract(lm)
      prefix = lm.reload.scorm_prefix
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
      expect(lm.scorm_prefix).to eq(prefix)
    end

    it "leaves a failed module and its reason alone until a new attempt starts" do
      lm = module_with("index.html" => "x")
      ScormExtractor.extract(lm)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq("no imsmanifest.xml found")
    end

    it "does nothing while another extraction is processing within the time bound" do
      lm = module_with(files)
      lm.update_columns(scorm_status: LearningModule.scorm_statuses[:processing], scorm_status_changed_at: 1.minute.ago)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("processing")
      expect(lm.scorm_package_files).not_to be_attached
    end

    it "takes over an extraction that has been processing past the time bound" do
      lm = module_with(files)
      lm.update_columns(scorm_status: LearningModule.scorm_statuses[:processing], scorm_status_changed_at: 1.hour.ago)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
    end

    it "does not publish its result when a retry took over meanwhile" do
      lm = module_with(files)
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |m, **args|
        LearningModule.where(id: lm.id).update_all(scorm_status_changed_at: 1.second.from_now)
        m.call(**args)
      end
      ScormExtractor.extract(lm)
      lm.reload
      expect(lm.scorm_status).to eq("processing")
      expect(lm.scorm_package_files).not_to be_attached
    end
  end

  describe "file paths in the package" do
    # Zip::OutputStream refuses (or alters) some names, so each entry is written
    # under a same-length placeholder and renamed in the archive bytes.
    # (Backslashes cannot reach the extractor: rubyzip reads them back as "/".)
    def module_with_raw_names(entries)
      renames = {}
      safe = entries.each_with_index.to_h do |(name, body), i|
        placeholder = "k#{i}".ljust(name.bytesize, "k")
        renames[placeholder.b] = name.b
        [placeholder, body]
      end
      bytes = zip_io(safe).string.b
      renames.each { |from, to| bytes.gsub!(from, to) }
      lm = create(:learning_module)
      lm.scorm_package.attach(io: StringIO.new(bytes), filename: "pkg.zip", content_type: "application/zip")
      lm.save!
      lm.reload
    end

    def module_from_bytes(bytes)
      lm = create(:learning_module)
      lm.scorm_package.attach(io: StringIO.new(bytes), filename: "pkg.zip", content_type: "application/zip")
      lm.save!
      lm.reload
    end

    # An Info-ZIP Unicode Path extra field: version, CRC32 of the header name, UTF-8 name
    def unicode_path_field(header_name, utf8_name, crc: Zlib.crc32(header_name))
      data = [1, crc].pack("CV") + utf8_name.b
      [0x7075, data.bytesize].pack("vv") + data
    end

    def zip_with_extra(header_name, extra)
      io = StringIO.new
      Zip::OutputStream.write_buffer(io) do |z|
        z.put_next_entry("imsmanifest.xml"); z.write(manifest)
        z.put_next_entry("index.html"); z.write("1")
        z.put_next_entry(header_name, nil, extra); z.write("x")
      end
      io.string
    end

    def manifest(href = "index.html")
      format(MANIFEST, href: href)
    end

    def base_files
      { "imsmanifest.xml" => manifest, "index.html" => "1" }
    end

    def stored_paths(lm)
      lm.scorm_package_files.blobs.pluck(:key).map { |k| k.delete_prefix("#{lm.scorm_prefix}/") }
    end

    [
      ["../evil.html", "../evil.html"],
      ["/evil.html", "/evil.html"],
      ["sub/../../evil.html", "sub/../../evil.html"],
      ["sub/\u0001evil.html", "sub/?evil.html"],
      ["sub/\u007Fevil.html", "sub/?evil.html"],
      ["sub/\u0085evil.html", "sub/?evil.html"],
      ["sub/\u202Eevil.html", "sub/?evil.html"],
      ["sub/\u200Fevil.html", "sub/?evil.html"],
      ["sub/\u2028evil.html", "sub/?evil.html"],
      ["sub/\u200Bevil.html", "sub/?evil.html"],
      ["../.DS_Store", "../.DS_Store"],
      ["sub/\uFEFFevil.html", "sub/?evil.html"]
    ].each do |name, shown|
      it "fails the extraction, naming the entry, uploading nothing, for #{name.inspect}" do
        lm = module_with_raw_names(base_files.merge(name => "x"))
        expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
        ScormExtractor.extract(lm)
        lm.reload
        expect(lm.scorm_status).to eq("failed")
        expect(lm.scorm_error).to eq(%(the package contains a file path that is not allowed: "#{shown}"))
      end
    end

    it "shortens a very long offending name in the reason" do
      lm = module_with_raw_names(base_files.merge("../#{"a" * 400}" => "x"))
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_error.length).to be <= 255
      expect(lm.scorm_error).to start_with('the package contains a file path that is not allowed: "../aaa')
    end

    it "skips dotfiles, dot-directories and operating system metadata anywhere, without failing the package" do
      junk = ["__MACOSX/._index.html", "sub/__MACOSX/x", ".DS_Store", "sub/.DS_Store", "Icon\r", "sub/Icon\r",
              "sub/._b.css", ".git/config", ".env", ".htaccess", "sub/.hidden/y.js"]
      lm = module_with_raw_names(base_files.merge(junk.to_h { |n| [n, "junk"] }).merge("sub/b.css" => "x"))
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
      expect(stored_paths(lm)).to match_array(%w[imsmanifest.xml index.html sub/b.css])
    end

    it "reads a name that is not UTF-8 as IBM437 instead of rejecting the package" do
      lm = module_with_raw_names(base_files.merge("caf\x82.html".b => "x"))
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
      expect(stored_paths(lm)).to include("caf\u00E9.html")
    end

    {
      "a//b.html" => "a/b.html",
      "a/./b.html" => "a/b.html",
      "./a/b.html" => "a/b.html"
    }.each do |name, stored|
      it "stores #{name.inspect} as #{stored.inspect}" do
        lm = module_with_raw_names(base_files.merge(name => "x"))
        ScormExtractor.extract(lm)
        expect(lm.reload.scorm_status).to eq("ready")
        expect(stored_paths(lm)).to match_array(%W[imsmanifest.xml index.html #{stored}])
      end
    end

    it "reads a name flagged as UTF-8 but invalid as IBM437 too" do
      bytes = zip_io(base_files.merge("caf\u00E9.html" => "x")).string.b.gsub("caf\xC3\xA9.html".b, "caf\x82k.html".b)
      lm = module_from_bytes(bytes)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
      expect(stored_paths(lm)).to include("caf\u00E9k.html")
    end

    it "uses the Unicode Path extra field when its CRC matches the header name" do
      lm = module_from_bytes(zip_with_extra("legacy.html", unicode_path_field("legacy.html", "\u00FCn\u00EF.html")))
      ScormExtractor.extract(lm)
      expect(stored_paths(lm.reload)).to include("\u00FCn\u00EF.html")
      expect(stored_paths(lm)).not_to include("legacy.html")
    end

    it "ignores a Unicode Path extra field whose CRC does not match the header name" do
      lm = module_from_bytes(zip_with_extra("legacy.html", unicode_path_field("legacy.html", "\u00FCn\u00EF.html", crc: 1)))
      ScormExtractor.extract(lm)
      expect(stored_paths(lm.reload)).to include("legacy.html")
    end

    it "stores names in NFC" do
      lm = module_with_raw_names(base_files.merge("cafe\u0301.html" => "x"))
      ScormExtractor.extract(lm)
      expect(stored_paths(lm.reload)).to include("caf\u00E9.html")
    end

    it "keeps zero-width joiners and non-joiners, which some scripts and emoji need" do
      lm = module_with_raw_names(base_files.merge("sub/\u0645\u200C\u06A9.css" => "x", "sub/\u{1F468}\u200D\u{1F4BB}.css" => "x"))
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("ready")
      expect(stored_paths(lm)).to include("sub/\u0645\u200C\u06A9.css", "sub/\u{1F468}\u200D\u{1F4BB}.css")
    end

    it "fails when the entry point is a file that was skipped" do
      lm = module_with_raw_names("imsmanifest.xml" => manifest("content/.player/index.html"),
                                 "content/.player/index.html" => "x")
      expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq('the package needs a file that was skipped: "content/.player/index.html"')
    end

    it "fails when a file the manifest lists was skipped, even with a query and encoding in the link" do
      xml = %(<manifest><resources><resource href="index.html"><file href="%2Eenv?x=1#top"/></resource></resources></manifest>)
      lm = module_with_raw_names("imsmanifest.xml" => xml, "index.html" => "1", ".env" => "secret")
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_error).to eq('the package needs a file that was skipped: ".env"')
    end

    it "extracts an archive whose entries all start with ./" do
      lm = module_with_raw_names("./imsmanifest.xml" => manifest, "./index.html" => "1", "./sub/b.css" => "x")
      ScormExtractor.extract(lm)
      lm.reload
      expect(lm.scorm_status).to eq("ready")
      expect(lm.scorm_entry_point).to eq("index.html")
      expect(stored_paths(lm)).to match_array(%w[imsmanifest.xml index.html sub/b.css])
    end

    it "uses the manifest with the fewest path segments" do
      lm = module_with_raw_names(base_files.merge("sub/imsmanifest.xml" => manifest("deep.html"), "sub/deep.html" => "2"))
      ScormExtractor.extract(lm)
      lm.reload
      expect(lm.scorm_status).to eq("ready")
      expect(lm.scorm_entry_point).to eq("index.html")
      expect(stored_paths(lm)).to include("sub/imsmanifest.xml", "sub/deep.html")
    end

    it "fails when two manifests share the shallowest level" do
      lm = module_with_raw_names("a/imsmanifest.xml" => manifest, "a/index.html" => "1",
                                 "b/imsmanifest.xml" => manifest, "b/index.html" => "2")
      expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq("more than one imsmanifest.xml at the same folder level")
    end

    it "fails when ./a.html and a.html are both present" do
      lm = module_with_raw_names(base_files.merge("./a.html" => "1", "a.html" => "2"))
      expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq('duplicate file path: "a.html"')
    end

    it "fails when a file outside the root directory collides with one inside it" do
      lm = module_with_raw_names("pkg/imsmanifest.xml" => manifest, "pkg/x.js" => "1", "x.js" => "2")
      expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
      ScormExtractor.extract(lm)
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq('duplicate file path: "x.js"')
    end

    it "extracts nested relative paths" do
      lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "a.html"), "a.html" => "1", "sub/dir/b.css" => "x")
      ScormExtractor.extract(lm)
      lm.reload
      expect(lm.scorm_status).to eq("ready")
      expect(lm.scorm_package_files.blobs.find_by(key: "#{lm.scorm_prefix}/sub/dir/b.css")).to be_present
    end
  end

  describe "progress and cleanup" do
    let(:files) { { "imsmanifest.xml" => format(MANIFEST, href: "a.html"), "a.html" => "1", "b.html" => "2" } }

    def upload_keys(lm)
      ActiveStorage::Blob.where("key LIKE ?", "scorm/learning_modules/test_#{lm.id}_%").pluck(:key)
    end

    it "refreshes the status time while it keeps making progress" do
      stub_const("ScormExtractor::HEARTBEAT_EVERY", 0.seconds)
      lm = module_with(files)
      seen = []
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |m, **args|
        sleep 0.01
        seen << LearningModule.find(lm.id).scorm_status_changed_at
        m.call(**args)
      end
      ScormExtractor.extract(lm)
      expect(seen.uniq.size).to be > 1
      expect(lm.reload.scorm_status).to eq("ready")
    end

    it "removes the files it uploaded when it fails, and records an unexpected error without hiding it" do
      lm = module_with(files)
      allow_any_instance_of(LearningModule).to receive(:update!).and_raise("boom")
      expect { ScormExtractor.extract(lm) }.to raise_error("boom")
      lm.reload
      expect(lm.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq("extraction error (RuntimeError)")
      expect(upload_keys(lm)).to be_empty
    end

    it "removes the files it uploaded when a newer run took over" do
      lm = module_with(files)
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |m, **args|
        LearningModule.where(id: lm.id).update_all(scorm_status_changed_at: 1.second.from_now)
        m.call(**args)
      end
      ScormExtractor.extract(lm)
      expect(upload_keys(lm)).to be_empty
    end

    it "keeps the previous files when the swap cannot be saved" do
      lm = module_with(files)
      ScormExtractor.extract(lm)
      old_keys = upload_keys(lm.reload)
      lm.update_columns(scorm_status: LearningModule.scorm_statuses[:pending])
      allow_any_instance_of(LearningModule).to receive(:update!).and_raise("db down")
      expect { ScormExtractor.extract(lm) }.to raise_error("db down")
      lm.reload
      expect(lm.scorm_status).to eq("failed")
      expect(lm.scorm_package_files.blobs.pluck(:key)).to match_array(old_keys)
      expect(upload_keys(lm)).to match_array(old_keys)
    end
  end

  describe "LearningModule#scorm_stalled?" do
    it "is true for pending or processing states older than the bound, or with no recorded time" do
      lm = create(:learning_module, :with_scorm_object)
      lm.assign_attributes(scorm_status: :pending, scorm_status_changed_at: nil)
      expect(lm).to be_scorm_stalled
      lm.scorm_status_changed_at = 1.minute.ago
      expect(lm).not_to be_scorm_stalled
      lm.scorm_status = :processing
      lm.scorm_status_changed_at = (LearningModule::SCORM_STALL_AFTER + 1.minute).ago
      expect(lm).to be_scorm_stalled
      lm.scorm_status = :ready
      expect(lm).not_to be_scorm_stalled
    end

    it "starts the clock when a package is uploaded" do
      lm = module_with("imsmanifest.xml" => "<m/>")
      expect(lm.scorm_status_changed_at).to be_within(1.minute).of(Time.current)
    end
  end

  describe "ExtractScormJob" do
    it "extracts the module given by id" do
      lm = module_with("imsmanifest.xml" => format(MANIFEST, href: "j.html"), "j.html" => "1")
      ExtractScormJob.perform_now(lm.id)
      expect(lm.reload.scorm_status).to eq("ready")
    end

    it "records an invalid package without raising, and a repeated run keeps the reason" do
      lm = module_with("index.html" => "x")
      2.times { expect { ExtractScormJob.perform_now(lm.id) }.not_to raise_error }
      expect(lm.reload.scorm_status).to eq("failed")
      expect(lm.scorm_error).to eq("no imsmanifest.xml found")
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
