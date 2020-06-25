module VideosHelper

  def bytes_to_megabytes(bytes)
    (bytes.to_f/1.megabyte).round(2)
  end

end
