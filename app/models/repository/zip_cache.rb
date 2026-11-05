# frozen_string_literal: true

require "open3"

# The zip a repository is downloaded as, and the disk cache of those zips (tmp/repository_zips).
#
# A zip is built once and kept while it is newer than the repository. The cache is bounded: the zips together
# stay under REPOSITORY_ZIP_CACHE_MAX_BYTES, the filesystem keeps REPOSITORY_ZIP_MIN_FREE_BYTES free, and the
# least recently used zips are removed to make room. A repository whose zip would exceed
# REPOSITORY_ZIP_MAX_CACHED_ZIP_BYTES is built for one response and not kept. Each file streams from storage
# straight into the zip; the zip is written under a temporary name and renamed when complete, and a failed build
# leaves nothing behind. Only files in the cache directory (and the repo_file* leftovers of the old build in the
# system temp directory) are ever deleted.
class Repository::ZipCache
  # +path+ is a cached zip to send; +entries+ are the files to stream into a response when there is no cached zip.
  # Both are empty when none of the repository's files could be found in storage.
  Result = Struct.new(:path, :entries, keyword_init: true) do
    def empty?
      path.nil? && entries.empty?
    end
  end

  GIGABYTE = 1024**3
  STALE_AFTER = 1.hour
  ENTRY_OVERHEAD = 1024
  TEMP_SUFFIX = ".tmp"
  # A zip modified more recently than this may be in use by a response or a build, so it is never evicted.
  EVICTION_GRACE = 5.minutes

  def self.directory
    Rails.root.join("tmp", "repository_zips")
  end

  def self.setting(name, default)
    Integer(ENV.fetch(name, default), exception: false) || default
  end

  def self.cache_max_bytes = setting("REPOSITORY_ZIP_CACHE_MAX_BYTES", 5 * GIGABYTE)
  def self.min_free_bytes = setting("REPOSITORY_ZIP_MIN_FREE_BYTES", 5 * GIGABYTE)
  def self.max_cached_zip_bytes = setting("REPOSITORY_ZIP_MAX_CACHED_ZIP_BYTES", GIGABYTE)

  # Bytes available to this process on the filesystem holding +path+.
  def self.free_bytes(path)
    out, status = Open3.capture2("df", "-Pk", path.to_s)
    raise "df failed" unless status.success?

    out.lines.last.split[3].to_i * 1024
  end

  # The recurring job: temporary files older than an hour, then the cap and the floor.
  def self.cleanup!(now: Time.current, directory: self.directory)
    cache = new(nil, directory: directory)
    cache.remove_stale_partials(now)
    cache.make_room(0, capped: true)
  end

  def initialize(repository, directory: self.class.directory)
    @repository = repository
    @directory = Pathname(directory)
  end

  def path
    @directory.join("makerepo_#{@repository.id}.zip")
  end

  # A cached zip when one is valid; otherwise a freshly built and cached one, or, when it is too large to keep or
  # the disk has no room, the entries to stream straight from storage into the response.
  def fetch
    FileUtils.mkdir_p(@directory)
    return Result.new(path: path, entries: []) if mark_used_if_fresh

    FileUtils.rm_f(path)
    entries = present_entries
    return Result.new(entries: []) if entries.empty?

    estimate = estimate_bytes(entries)
    return Result.new(entries: entries) unless cacheable?(estimate)
    return unkept(entries, estimate) unless make_room(estimate, capped: true)

    Result.new(path: build(entries), entries: [])
  end

  # Writes the entries into a zip streamer, each file straight from storage.
  def self.write_entries(zip, entries)
    entries.each do |name, attachment|
      zip.write_file(name) { |sink| attachment.download { |chunk| sink << chunk } }
    end
  end

  # Evicts least recently used zips (down to none) until +needed+ more bytes fit under the cap (when +capped+)
  # and above the free-space floor. False when nothing evictable is left and it still does not fit.
  def make_room(needed, capped:)
    zips = zips_by_use
    total = zips.sum { |zip| zip[:size] }
    free = self.class.free_bytes(@directory)
    until fits?(total, free, needed, capped)
      victim = zips.shift or return false
      total -= victim[:size]
      free += victim[:size] if FileUtils.rm_f(victim[:path])
    end
    true
  end

  # Partial builds in the cache directory and repo_file* leftovers of the old build, older than an hour.
  def remove_stale_partials(now)
    cutoff = now - STALE_AFTER
    stale = Dir.glob(@directory.join("*#{TEMP_SUFFIX}").to_s) + Dir.glob(File.join(Dir.tmpdir, "repo_file*"))
    stale.each do |file|
      next unless File.file?(file) && !File.symlink?(file) && File.mtime(file) < cutoff

      FileUtils.rm_f(file)
    end
  end

  private

  def mark_used_if_fresh
    return false unless File.exist?(path) && File.mtime(path) > @repository.updated_at

    File.utime(Time.now, File.mtime(path), path)
    true
  rescue Errno::ENOENT
    false
  end

  # [name, attachment] for every file that is in storage; a duplicate name gets its index as a prefix.
  def present_entries
    names = Set.new
    @repository.repo_files.includes(file_attachment: :blob).each_with_index.filter_map do |file, index|
      attachment = file.file
      next unless attachment.attached? && in_storage?(attachment)

      name = attachment.filename.to_s
      name = "#{index}_#{name}" if names.include?(name)
      names << name
      [name, attachment]
    end
  end

  def in_storage?(attachment)
    return true if attachment.blob.service.exist?(attachment.blob.key)

    Rails.logger.warn("Attachment #{attachment.blob.key} missing in S3, skipping.")
    false
  end

  def estimate_bytes(entries)
    entries.sum { |_name, attachment| attachment.blob.byte_size + ENTRY_OVERHEAD }
  end

  def cacheable?(estimate)
    estimate <= [self.class.max_cached_zip_bytes, self.class.cache_max_bytes].min
  end

  def fits?(total, free, needed, capped)
    (!capped || total + needed <= self.class.cache_max_bytes) && free - needed >= self.class.min_free_bytes
  end

  def zips_by_use
    recent = Time.now - EVICTION_GRACE
    zips = Dir.glob(@directory.join("makerepo_*.zip").to_s).filter_map do |zip|
      stat = File.stat(zip)
      next if stat.mtime > recent

      { path: zip, size: stat.size, used: stat.atime }
    rescue Errno::ENOENT
      nil
    end
    zips.sort_by { |zip| zip[:used] }
  end

  # The cache is empty and the disk is still below the floor: stream the zip without touching the disk.
  def unkept(entries, estimate)
    Rails.error.report(RuntimeError.new("repository zip cache is empty and the disk is below the free-space floor"),
                       handled: true, severity: :warning,
                       context: { repository_id: @repository.id, estimate: estimate })
    Result.new(entries: entries)
  end

  def build(entries)
    temp = @directory.join("makerepo_#{@repository.id}.#{SecureRandom.hex(6)}#{TEMP_SUFFIX}")
    File.open(temp, "wb") { |io| ZipKit::Streamer.open(io) { |zip| self.class.write_entries(zip, entries) } }
    File.rename(temp, path)
    path
  rescue StandardError
    FileUtils.rm_f(temp) if temp
    raise
  end
end
