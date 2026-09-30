# frozen_string_literal: true

require "zlib"

module Wp2txt
  # Streams the rows of one table's INSERT statements out of an official
  # MySQL table dump (.sql or .sql.gz), without loading the file whole.
  #
  # Dumps write each INSERT either on one line or with the header on its own
  # line and one tuple per following line (current dumps do the latter), so
  # every line of a statement is read up to its terminating semicolon.
  # Statements for other tables are skipped.
  #
  # Lines are read as BINARY: string columns are VARBINARY and real dumps
  # contain historically corrupted bytes. Callers match tuples with ASCII-only
  # patterns and validate the captures themselves.
  module SqlDumpReader
    STATEMENT_START = /\A\s*INSERT\s+INTO\s/i

    module_function

    # @yield [String] each line (BINARY) that belongs to an INSERT statement for table
    def each_insert_line(source_path, table)
      header = /\A\s*INSERT\s+INTO\s+`#{Regexp.escape(table)}`\s+VALUES\b/i
      io = if source_path.end_with?(".gz")
             # GzipReader ignores set_encoding; the encoding must be given at open time
             Zlib::GzipReader.open(source_path, encoding: Encoding::BINARY.to_s)
           else
             File.open(source_path, "rb")
           end
      inside = false
      begin
        io.each_line do |line|
          inside = header.match?(line) if STATEMENT_START.match?(line)
          next unless inside

          inside = false if line.rstrip.end_with?(";")
          yield line
        end
      ensure
        io.close
      end
    end

    UNESCAPE_REGEX = /\\(.)/m
    # MySQL backslash escapes inside mysqldump string literals
    UNESCAPES = {
      "0" => "\0", "'" => "'", '"' => '"', "b" => "\b", "n" => "\n",
      "r" => "\r", "t" => "\t", "Z" => "\x1A", "\\" => "\\"
    }.freeze

    # Undo MySQL string escaping (\' \\ \n ...) in a captured value
    def unescape(value)
      value.gsub(UNESCAPE_REGEX) { UNESCAPES.fetch(Regexp.last_match(1), Regexp.last_match(1)) }
    end
  end
end
