class Magick::Image
  def resize_to_fill(ncols, nrows=nil, gravity=CenterGravity)
    copy.resize_to_fill!(ncols, nrows, gravity)
  end

  def resize_to_fill!(ncols, nrows=nil, gravity=CenterGravity)
    nrows ||= ncols
    if ncols != columns || nrows != rows
      scale = [ncols/columns.to_f, nrows/rows.to_f].max
      resize!(scale*columns+0.5, scale*rows+0.5)
    end
    crop!(gravity, ncols, nrows, true) if ncols != columns || nrows != rows
    self
  end
end
