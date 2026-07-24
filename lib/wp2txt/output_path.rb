# frozen_string_literal: true

module Wp2txt
  # Server-side output path confinement shared by the file-writing tools
  # (extract_corpus / start_extract_job / query_sql with output_path).
  # Paths must resolve under the server's output directory — an agent mixing
  # up paths must not be able to clobber arbitrary user files — and existing
  # files are not replaced unless overwrite is set.
  module OutputPath
    module_function

    # @return [String] the confined, absolute output path
    # @raise [ArgumentError] when the path escapes base_dir or the file exists
    def confine(output_path, base_dir, overwrite: false)
      path = File.expand_path(output_path, base_dir)
      base = File.expand_path(base_dir)
      unless path == base || path.start_with?(base + File::SEPARATOR)
        raise ArgumentError, "output_path must stay within the server output directory (#{base})"
      end
      if File.exist?(path) && !overwrite
        raise ArgumentError, "output file already exists: #{path} (pass overwrite: true to replace it)"
      end

      path
    end
  end
end
