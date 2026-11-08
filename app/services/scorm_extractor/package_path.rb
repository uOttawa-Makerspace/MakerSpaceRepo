# One zip entry's path. Every entry goes through here once; the extractor
# never looks at raw names.
class ScormExtractor
  class PackagePath
    # Control, format (bidi marks, zero-width space, BOM, soft hyphen), line and
    # paragraph separators. The zero-width (non-)joiners stay: Persian, Arabic,
    # Indic and emoji names need them.
    UNSAFE_CHARACTERS = /(?![\u200C\u200D])[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/
    # Operating system metadata that zipped folders carry
    NON_CONTENT_SEGMENTS = ['__MACOSX', "Icon\r"].freeze
    UNICODE_PATH_FIELD = [0x7075].pack('v') # Info-ZIP Unicode Path extra field

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

    # Checked on every entry, before non_content?, so a traversal is never
    # excused as junk. The Finder's "Icon\r" file is the one name allowed a
    # control character.
    def unsafe?
      name.start_with?('/') || segments.include?('..') ||
        name.split('/').reject { |segment| segment == "Icon\r" }.any? { |segment| segment.match?(UNSAFE_CHARACTERS) }
    end

    # The path as stored: without the package's root directory (paths outside it are kept)
    def rooted(root_segments)
      segments.first(root_segments.size) == root_segments ? segments.drop(root_segments.size) : segments
    end

    def display
      name.gsub(UNSAFE_CHARACTERS, '?').truncate(120)
    end

    private

    # The entry's own UTF-8 name (Info-ZIP extra field), else UTF-8 when the
    # bytes are valid, else the zip format's legacy code page. An encoding never
    # fails a package. Always NFC, so names from macOS (NFD) meet NFC links.
    def decode(entry)
      raw = entry.name.b
      utf8 = raw.dup.force_encoding(Encoding::UTF_8)
      decoded =
        if (unicode = unicode_path(entry, raw))
          unicode
        elsif utf8.valid_encoding?
          utf8
        else
          raw.force_encoding(Encoding::IBM437).encode(Encoding::UTF_8)
        end
      decoded.unicode_normalize(:nfc)
    end

    # Version 1 of the field: a CRC32 of the header name, then the UTF-8 name.
    # Only trusted while the CRC still matches the name in the header.
    def unicode_path(entry, raw)
      extra = entry.extra[:unknown]
      return unless extra

      [extra.to_c_dir_bin, extra.to_local_bin].each do |bytes|
        pos = 0
        while pos + 4 <= bytes.bytesize
          size = bytes.byteslice(pos + 2, 2).unpack1('v')
          data = bytes.byteslice(pos + 4, size).to_s
          if bytes.byteslice(pos, 2) == UNICODE_PATH_FIELD && data.bytesize > 5 && data.getbyte(0) == 1 &&
               data.byteslice(1, 4).unpack1('V') == Zlib.crc32(raw)
            name = data.byteslice(5..).force_encoding(Encoding::UTF_8)
            return name if name.valid_encoding?
          end
          pos += 4 + size
        end
      end
      nil
    end
  end
end
