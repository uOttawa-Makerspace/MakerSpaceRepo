# Rack body for one SCORM asset response: the first slice, already read, then
# the rest of the range from storage in slices, so memory stays bounded by the
# slice. The response promised its Content-Length, so a storage failure or a
# short read while iterating is reported and raised, never resumed or turned
# into a response: the connection is cut short and the client sees a truncated
# body rather than a complete-looking one. Errors raised from the consumer (the
# client side, such as a closed connection) pass through untouched.
class ScormAssetBody
  SLICE = 1.megabyte

  class ShortRead < StandardError
  end

  # Reads the first slice, so the caller can refuse before sending any header.
  # Storage errors (FileNotFoundError among them) are for the caller to map.
  def self.open(blob, range)
    new(blob, range, fetch(blob, range.begin..[range.end, range.begin + SLICE - 1].min))
  end

  def self.fetch(blob, span)
    chunk = blob.download_chunk(span)
    raise ShortRead, "expected #{span.size} bytes, got #{chunk.bytesize}" unless chunk.bytesize == span.size

    chunk
  end

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
      yield read(from..to)
      from = to + 1
    end
  end

  private

  def read(span)
    self.class.fetch(@blob, span)
  rescue StandardError => e
    Rails.logger.error "SCORM asset stream failed (#{e.class}) for blob #{@blob.id}"
    Rails.error.report(e, handled: false, context: { blob_id: @blob.id })
    raise
  end
end
