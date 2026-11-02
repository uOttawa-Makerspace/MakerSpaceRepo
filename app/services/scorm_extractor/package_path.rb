# One zip entry's path. Every entry goes through here once; the extractor
# never looks at raw names.
class ScormExtractor
  class PackagePath
    # Control, format (bidi marks, zero-width, BOM, soft hyphen), line and paragraph separators
    UNSAFE_CHARACTERS = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/
    # Operating system metadata that zipped folders carry
    NON_CONTENT_SEGMENTS = ['__MACOSX', "Icon\r"].freeze
    UTF8_FLAG = 0x800

    attr_reader :entry, :name, :segments

    def initialize(entry)
      @entry = entry
      @name = decode(entry)
      # rubyzip has already turned backslashes into slashes
      @segments = name.split('/').reject { |segment| segment.empty? || segment == '.' }
    end

    # Dotfiles and dot-directories, and OS metadata, anywhere in the path
    def non_content?
      segments.empty? ||
        segments.any? { |s| NON_CONTENT_SEGMENTS.include?(s) || (s.start_with?('.') && s != '..') }
    end

    def unsafe?
      name.start_with?('/') || segments.include?('..') || name.match?(UNSAFE_CHARACTERS)
    end

    # The path as stored: without the package's root directory (paths outside it are kept)
    def rooted(root_segments)
      segments.first(root_segments.size) == root_segments ? segments.drop(root_segments.size) : segments
    end

    def display
      name.gsub(UNSAFE_CHARACTERS, '?').truncate(120)
    end

    private

    # UTF-8 when flagged or valid as such, otherwise the zip format's legacy
    # code page. An encoding never fails a package.
    def decode(entry)
      raw = entry.name.b
      utf8 = raw.dup.force_encoding(Encoding::UTF_8)
      return utf8.scrub('?') if entry.gp_flags.to_i & UTF8_FLAG != 0 || utf8.valid_encoding?

      raw.force_encoding(Encoding::IBM437).encode(Encoding::UTF_8)
    end
  end
end
