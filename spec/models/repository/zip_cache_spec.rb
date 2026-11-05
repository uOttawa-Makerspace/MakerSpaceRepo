# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repository::ZipCache do
  let(:dir) { Pathname(Dir.mktmpdir("zipcache")) }
  let(:big_free) { 100 * described_class::GIGABYTE }

  before do
    allow(described_class).to receive(:free_bytes).and_return(big_free)
  end

  after do
    FileUtils.rm_rf(dir.to_s)
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

    it "evicts nothing and reports when df output is garbled" do
      allow(described_class).to receive(:free_bytes).and_call_original
      allow(Open3).to receive(:capture2).and_return(["Filesystem 1024-blocks Used Available\n/dev/x 100 50 -\n", instance_double(Process::Status, success?: true)])
      zip = make_zip("makerepo_1.zip", 50, used: Time.now - 1.hour)
      expect(Rails.error).to receive(:report).with(instance_of(described_class::UnreadableSpace), anything).at_least(:once)
      expect(described_class.new(nil, directory: dir).make_room(0, capped: true)).to be(true)
      described_class.cleanup!(directory: dir)
      expect(zip).to exist
    end

    it "does not evict a zip used a moment ago" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_MIN_FREE_BYTES" => "1000"))
      allow(described_class).to receive(:free_bytes).and_return(0)
      zip = make_zip("makerepo_1.zip", 50, used: Time.now - 1.minute)
      expect(described_class.new(nil, directory: dir).make_room(0, capped: true)).to be(false)
      expect(zip).to exist
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
      zip = make_zip("makerepo_1.zip", 50, used: Time.now - 1.hour)
      expect(described_class.new(nil, directory: dir).make_room(0, capped: true)).to be(false)
      expect(zip).not_to exist
    end

    it "ignores the cap for a zip that is not kept" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "10"))
      zip = make_zip("makerepo_1.zip", 100, used: Time.now - 1.hour)
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
    it "deletes only only old partial zips, and keeps valid zips and other files" do
      stub_const("ENV", ENV.to_h.merge("REPOSITORY_ZIP_CACHE_MAX_BYTES" => "1000000"))
      old_partial = age(dir.join("makerepo_9.abc.tmp").tap { |f| File.write(f, "p") }, 2.hours)
      new_partial = dir.join("makerepo_8.abc.tmp").tap { |f| File.write(f, "p") }
      valid_zip = age(dir.join("makerepo_7.zip").tap { |f| File.write(f, "z") }, 3.hours)
      other_in_dir = age(dir.join("notes.txt").tap { |f| File.write(f, "n") }, 3.hours)

      described_class.cleanup!(directory: dir)

      expect(old_partial).not_to exist
      expect([new_partial, valid_zip, other_in_dir].map(&:exist?)).to all(be(true))
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
