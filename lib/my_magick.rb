class Magick::Image
  def resize_to_fit!(cols, rows)
    change_geometry(Magick::Geometry.new(cols, rows)) do |ncols, nrows|
      resize!(ncols, nrows)
    end
  end

  def resize_to_fit(cols, rows)
    change_geometry(Magick::Geometry.new(cols, rows)) do |ncols, nrows|
      resize(ncols, nrows)
    end
  end
end
