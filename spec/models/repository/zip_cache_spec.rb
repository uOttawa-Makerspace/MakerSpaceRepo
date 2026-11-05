# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repository::ZipCache do
  let(:dir) { Pathname(Dir.mktmpdir("zipcache")) }
  let(:tmp) { Pathname(Dir.mktmpdir("systmp")) }
  let(:big_free) { 100 * described_class::GIGABYTE }

  before do
    allow(Dir).to receive(:tmpdir).and_return(tmp.to_s)
    allow(described_class).to receive(:free_bytes).and_return(big_free)
  end

  after do
    FileUtils.rm_rf([dir, tmp].map(&:to_s))
  end

  def make_zip(name, bytes, used:)
    file = dir.join(name)
    File.binwrite(file, "x" * bytes)
    File.utime(used, Time.now - 1.hour, file)
    file
  end

  def age(file, by)
    t = Time.now - by
    File.utime(t, t, file)
    file
  end

  describe "#make_room" do
    it "removes the least recently used zip when the cap is exceeded" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "300"))
      oldest = make_zip("makerepo_1.zip", 100, used: Time.now - 3.hours)
      middle = make_zip("makerepo_2.zip", 100, used: Time.now - 2.hours)
      newest = make_zip("makerepo_3.zip", 100, used: Time.now - 1.hour)
      expect(described_class.new(nil, directory: dir).make_room(100, capped: true)).to be(true)
      expect([oldest.exist?, middle.exist?, newest.exist?]).to eq([false, true, true])
    end

    it "with low disk evicts the oldest of three zips first and stops as soon as there is room" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_MIN_FREE_BYTES" => "1000"))
      allow(described_class).to receive(:free_bytes).and_return(800)
      zips = [3, 2, 1].map { |hours| make_zip("makerepo_#{hours}.zip", 150, used: Time.now - hours.hours) }
      cache = described_class.new(nil, directory: dir)
      expect(cache.make_room(0, capped: true)).to be(true)
      expect(zips.map(&:exist?)).to eq([false, false, true])
    end

    it "does not evict a zip modified in the last minutes" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_MIN_FREE_BYTES" => "1000"))
      allow(described_class).to receive(:free_bytes).and_return(0)
      fresh = dir.join("makerepo_1.zip").tap { |f| File.write(f, "z") }
      expect(described_class.new(nil, directory: dir).make_room(0, capped: true)).to be(false)
      expect(fresh).to exist
    end

    it "evicts for the free-space floor and reports when it still does not fit" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_MIN_FREE_BYTES" => "1000"))
      allow(described_class).to receive(:free_bytes).and_return(900)
      zip = make_zip("makerepo_1.zip", 50, used: Time.now)
      expect(described_class.new(nil, directory: dir).make_room(0, capped: true)).to be(false)
      expect(zip).not_to exist
    end

    it "ignores the cap for a zip that is not kept" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "10"))
      zip = make_zip("makerepo_1.zip", 100, used: Time.now)
      expect(described_class.new(nil, directory: dir).make_room(500, capped: false)).to be(true)
      expect(zip).to exist
    end
  end

  describe ".free_bytes" do
    it "reads the available space of a real directory" do
      allow(described_class).to receive(:free_bytes).and_call_original
      expect(described_class.free_bytes(dir)).to be > 0
    end
  end

  describe ".cleanup!" do
    it "deletes only old partial zips and old repo_file temp files, and keeps the rest" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "1000000"))
      old_partial = age(dir.join("makerepo_9.abc.tmp").tap { |f| File.write(f, "p") }, 2.hours)
      new_partial = dir.join("makerepo_8.abc.tmp").tap { |f| File.write(f, "p") }
      valid_zip = age(dir.join("makerepo_7.zip").tap { |f| File.write(f, "z") }, 3.hours)
      other_in_dir = age(dir.join("notes.txt").tap { |f| File.write(f, "n") }, 3.hours)
      old_temp = age(tmp.join("repo_file20260101-1-x.txt").tap { |f| File.write(f, "t") }, 2.hours)
      new_temp = tmp.join("repo_file20260101-2-y.txt").tap { |f| File.write(f, "t") }
      unrelated = age(tmp.join("other_file.txt").tap { |f| File.write(f, "u") }, 5.hours)
      old_dir = age(tmp.join("repo_file_dir").tap(&:mkpath), 5.hours)

      described_class.cleanup!(directory: dir)

      expect([old_partial, old_temp].map(&:exist?)).to eq([false, false])
      expect([new_partial, valid_zip, other_in_dir, new_temp, unrelated, old_dir].map(&:exist?)).to all(be(true))
    end

    it "trims the cache to its cap, least recently used first" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "150"))
      old = make_zip("makerepo_1.zip", 100, used: Time.now - 2.hours)
      recent = make_zip("makerepo_2.zip", 100, used: Time.now - 1.hour)
      described_class.cleanup!(directory: dir)
      expect([old.exist?, recent.exist?]).to eq([false, true])
    end
  end

  it "is run by the recurring job" do
    expect(described_class).to receive(:cleanup!)
    RepositoryZipCacheCleanupJob.perform_now
  end
end
