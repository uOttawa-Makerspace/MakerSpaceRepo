# Rack body for one SCORM asset response: the slice already read, then the rest
# of the range from storage in slices, so memory stays bounded by the slice.
# A failure while iterating is logged and raised, not turned into a response:
# the response promised its Content-Length, so the connection is cut short and
# the client sees a truncated body rather than a complete-looking one.
class ScormAssetBody
  SLICE = 1.megabyte
  CLIENT_DISCONNECTS = [Errno::EPIPE, Errno::ECONNRESET, IOError].freeze

  def initialize(blob, range, first_slice)
    @blob = blob
    @range = range
    @first_slice = first_slice
  end

  def each
    yield @first_slice
    from = @range.begin + @first_slice.bytesize
    while from <= @range.end
      to = [from + SLICE - 1, @range.end].min
      yield @blob.download_chunk(from..to)
      from = to + 1
    end
  rescue StandardError => e
    Rails.logger.error "SCORM asset stream failed (#{e.class}) for blob #{@blob.id}" unless CLIENT_DISCONNECTS.any? { |c| e.is_a?(c) }
    raise
  end
end
