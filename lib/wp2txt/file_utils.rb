# frozen_string_literal: true

require "find"

module Wp2txt
  # File operation utilities

  # Collect filenames recursively
  def collect_files(str, regex = nil)
    regex ||= //
    text_array = []
    Find.find(str) do |f|
      text_array << f if regex =~ f
    end
    text_array.sort
  end

  # Modify a file using block/yield mechanism
  def file_mod(file_path, backup = false)
    str = File.read(file_path)
    newstr = yield(str)
    str = newstr unless newstr.nil?

    require "tempfile"
    dir = File.dirname(file_path)
    temp = Tempfile.new(["wp2txt_", File.extname(file_path)], dir)
    begin
      temp.write(str)
      temp.close
      File.rename(file_path, file_path + ".bak")
      File.rename(temp.path, file_path)
      File.unlink(file_path + ".bak") unless backup
    rescue StandardError
      temp.close! rescue nil # rubocop:disable Style/RescueModifier
      raise
    end
  end

  # Modify files under a directory (recursive)
  def batch_file_mod(dir_path)
    if FileTest.directory?(dir_path)
      collect_files(dir_path).each do |file|
        yield file if FileTest.file?(file)
      end
    elsif FileTest.file?(dir_path)
      yield dir_path
    end
  end

  # Take care of difference of separators among environments
  def correct_separator(input)
    case input
    when String
      # Use tr instead of gsub for simple character replacement (faster)
      if RUBY_PLATFORM.index("win32")
        input.tr("/", "\\")
      else
        input.tr("\\", "/")
      end
    when Array
      input.map { |item| correct_separator(item) }
    end
  end

  def rename(files, ext = "txt")
    # num of digits necessary to name the last file generated
    maxwidth = 0

    files.each do |f|
      width = f.slice(/-(\d+)\z/, 1).to_s.length.to_i
      maxwidth = width if maxwidth < width
      newname = f.sub(/-(\d+)\z/) do
        "-" + format("%0#{maxwidth}d", $1.to_i)
      end
      File.rename(f, newname + ".#{ext}")
    end
    true
  end

  # Convert int of seconds to string in the format 00:00:00
  def sec_to_str(int)
    unless int
      str = "--:--:--"
      return str
    end
    h = int / 3600
    m = (int - h * 3600) / 60
    s = int % 60
    format("%02d:%02d:%02d", h, m, s)
  end
end
