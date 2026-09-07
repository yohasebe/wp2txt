# frozen_string_literal: true

require "tempfile"
require "tmpdir"

module Wp2txt
  # Output directories are dedicated, trusted directories. Reject links below
  # the trusted platform temp root (whose ancestors may be OS aliases on macOS).
  # This does not defend against an attacker replacing parent directories.
  module OutputPath
    module_function

    def reject_symlinks!(path)
      current = File.expand_path(path)
      temp_roots = [File.expand_path(Dir.tmpdir), File.realpath(Dir.tmpdir)]
      loop do
        raise ArgumentError, "symbolic links are not allowed in output paths: #{current}" if File.symlink?(current)
        parent = File.dirname(current)
        break if parent == current || temp_roots.include?(current)

        current = parent
      end
    end

    def validate_pair!(path, overwrite: false)
      [path, "#{path}.meta.json"].each do |destination|
        reject_symlinks!(destination)
        if File.exist?(destination) && !overwrite
          raise ArgumentError, "output file already exists: #{destination} (pass overwrite: true to replace it)"
        end
        if File.exist?(destination) && !File.file?(destination)
          raise ArgumentError, "output destination must be a file: #{destination}"
        end
      end
    end

    # Return the confined absolute path; the writer repeats validation and
    # reserves both destinations with EXCL to close the check/create race.
    def confine(output_path, base_dir, overwrite: false)
      path = File.expand_path(output_path, base_dir)
      base = File.expand_path(base_dir)
      unless path.start_with?(base + File::SEPARATOR)
        raise ArgumentError, "output_path must stay within the server output directory (#{base})"
      end
      validate_pair!(path, overwrite: overwrite)
      path
    end

    # Reserve destinations, stage both files, then publish with rename. EXCL
    # reservations are empty until publication; the pair is not a transaction.
    # Failure removes only reservations owned by this call, never prior output.
    def write_pair(path, overwrite: false)
      validate_pair!(path, overwrite: overwrite)
      destinations = [path, "#{path}.meta.json"]
      reservations = {}
      temporary = []
      begin
        unless overwrite
          destinations.each do |destination|
            File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
              reservations[destination] = file.stat
            end
          end
        end
        destinations.each do |destination|
          temporary << Tempfile.create([".wp2txt-", ".partial"], File.dirname(destination))
          temporary.last.close
        end
        result = yield(*temporary.map(&:path))
        destinations.each_with_index do |destination, index|
          reject_symlinks!(destination)
          File.rename(temporary[index].path, destination)
          reservations.delete(destination)
        end
        result
      rescue Errno::EEXIST => e
        raise ArgumentError, "output file already exists: #{e.message} (pass overwrite: true to replace it)"
      ensure
        temporary.each { |file| File.unlink(file.path) if File.exist?(file.path) }
        reservations.each do |destination, stat|
          current = File.lstat(destination) rescue nil
          File.unlink(destination) if current && current.dev == stat.dev && current.ino == stat.ino
        end
      end
    end
  end
end
