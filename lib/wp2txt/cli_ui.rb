# frozen_string_literal: true

require "pastel"
require "tty-spinner"
require "tty-progressbar"
require_relative "constants"

module Wp2txt
  # CLI UI helper module for consistent styling
  module CliUI
    # Exit codes for CLI
    EXIT_SUCCESS = 0
    EXIT_ERROR = 1
    EXIT_PARTIAL = 2  # Partial success (e.g., some articles not found)

    # Icons for status indicators
    ICONS = {
      success: "✔",
      error: "✖",
      warning: "!",
      info: "ℹ",
      arrow: "→",
      bullet: "•",
      check: "✓",
      cross: "✗",
      star: "★"
    }.freeze

    # Configure UI settings
    # @param no_color [Boolean] Disable colors
    # @param quiet [Boolean] Suppress progress output
    def configure_ui(no_color: false, quiet: false)
      @no_color = no_color || color_disabled_by_env?
      @quiet = quiet
    end

    # Check if color is disabled by environment
    # @return [Boolean]
    def color_disabled_by_env?
      # NO_COLOR is a standard: https://no-color.org/
      ENV.key?("NO_COLOR") || ENV["TERM"] == "dumb"
    end

    # Check if quiet mode is enabled
    # @return [Boolean]
    def quiet?
      @quiet || false
    end

    # Check if color is disabled
    # @return [Boolean]
    def no_color?
      @no_color || false
    end

    # Initialize pastel for colors
    def pastel
      @pastel ||= Pastel.new(enabled: !no_color?)
    end

    # Reset pastel instance (needed after configure_ui)
    def reset_pastel!
      @pastel = nil
    end

    # Print a section header with optional step indicator
    # @param title [String] Section title
    # @param step [Integer, nil] Current step number
    # @param total_steps [Integer, nil] Total number of steps
    def print_header(title, step: nil, total_steps: nil)
      return if quiet?

      puts
      if step && total_steps
        step_indicator = pastel.dim("[#{step}/#{total_steps}]")
        puts "#{step_indicator} #{pastel.cyan.bold(title)}"
      else
        puts pastel.cyan.bold("═══ #{title} ═══")
      end
    end

    # Print a sub-header
    # @param title [String] Sub-header title
    def print_subheader(title)
      return if quiet?

      puts
      puts pastel.bold("─── #{title} ───")
    end

    # Print key-value info line
    # @param key [String] Label
    # @param value [String] Value
    # @param indent [Integer] Indentation level
    def print_info(key, value, indent: 0)
      return if quiet?

      prefix = "  " * indent
      puts "#{prefix}#{pastel.dim(key + ":")} #{value}"
    end

    # Print a success message
    # @param message [String] Message
    def print_success(message)
      return if quiet?

      puts "#{pastel.green(ICONS[:success])} #{message}"
    end

    # Print an error message (always shown, even in quiet mode)
    # @param message [String] Message
    def print_error(message)
      # Errors are always shown
      $stderr.puts "#{pastel.red(ICONS[:error])} #{message}"
    end

    # Print a warning message (always shown, even in quiet mode)
    # @param message [String] Message
    def print_warning(message)
      # Warnings are always shown
      $stderr.puts "#{pastel.yellow(ICONS[:warning])} #{message}"
    end

    # Print an info message
    # @param message [String] Message
    def print_info_message(message)
      return if quiet?

      puts "#{pastel.blue(ICONS[:info])} #{message}"
    end

    # Print a list item with status
    # @param text [String] Item text
    # @param status [Symbol] :success, :error, :warning, :pending
    # @param indent [Integer] Indentation level
    def print_list_item(text, status: :pending, indent: 1)
      return if quiet?

      prefix = "  " * indent
      icon = case status
             when :success then pastel.green(ICONS[:check])
             when :error then pastel.red(ICONS[:cross])
             when :warning then pastel.yellow(ICONS[:warning])
             else pastel.dim(ICONS[:bullet])
             end
      puts "#{prefix}#{icon} #{text}"
    end

    # Print a completion summary box (always shown, even in quiet mode)
    # @param title [String] Summary title
    # @param stats [Hash] Statistics to display
    # @param status [Symbol] :success, :warning, :error
    def print_summary(title, stats, status: :success)
      # Summary is always shown (it's the final result)
      puts
      color = case status
              when :success then :green
              when :warning then :yellow
              when :error then :red
              else :white
              end

      # Calculate box width based on content
      width = 40
      title_line = " #{title}"
      content_lines = stats.map { |k, v| "  #{k}: #{v}" }

      # Draw box
      puts pastel.send(color, "┌#{"─" * width}┐")
      puts pastel.send(color, "│") + pastel.bold(title_line.ljust(width)) + pastel.send(color, "│")
      puts pastel.send(color, "├#{"─" * width}┤")

      content_lines.each do |line|
        puts pastel.send(color, "│") + line.ljust(width) + pastel.send(color, "│")
      end

      puts pastel.send(color, "└#{"─" * width}┘")
    end

    # Print elapsed time
    # @param seconds [Float] Elapsed seconds
    def print_elapsed_time(seconds)
      return if quiet?

      formatted = format_duration(seconds)
      puts pastel.dim("Completed in #{formatted}")
    end

    # Format duration in human-readable form
    # @param seconds [Float] Duration in seconds
    # @return [String] Formatted duration
    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        mins = (seconds / 60).floor
        secs = (seconds % 60).round
        "#{mins}m #{secs}s"
      else
        hours = (seconds / 3600).floor
        mins = ((seconds % 3600) / 60).floor
        "#{hours}h #{mins}m"
      end
    end

    # Format file size in human-readable form
    # @param bytes [Integer] Size in bytes
    # @return [String] Formatted size
    def format_size(bytes)
      Wp2txt.format_file_size(bytes)
    end

    # Create a spinner with consistent styling
    # @param message [String] Spinner message
    # @return [TTY::Spinner, NullSpinner] Configured spinner or null spinner in quiet mode
    def create_spinner(message)
      return NullSpinner.new if quiet?

      TTY::Spinner.new(
        "[:spinner] #{message}",
        format: :dots,
        hide_cursor: true
      )
    end

    # Create a progress bar with consistent styling
    # @param message [String] Progress message
    # @param total [Integer] Total count
    # @return [TTY::ProgressBar, NullProgressBar] Configured progress bar or null in quiet mode
    def create_progress_bar(message, total)
      return NullProgressBar.new if quiet?

      TTY::ProgressBar.new(
        "#{message} [:bar] :percent (:current/:total) :eta",
        total: total,
        bar_format: :block,
        width: 30,
        hide_cursor: true
      )
    end

    # Create a download progress bar
    # @param filename [String] File being downloaded
    # @param total_bytes [Integer] Total size in bytes
    # @return [TTY::ProgressBar, NullProgressBar] Configured progress bar or null in quiet mode
    def create_download_bar(filename, total_bytes)
      return NullProgressBar.new if quiet?

      size_str = format_size(total_bytes)
      TTY::ProgressBar.new(
        "  #{filename} [:bar] :percent (:eta)",
        total: total_bytes,
        bar_format: :block,
        width: 25,
        hide_cursor: true,
        unknown: "#{size_str} (size unknown)"
      )
    end

    # Prompt for confirmation
    # @param message [String] Prompt message
    # @param default [Boolean] Default response
    # @return [Boolean] User response
    def confirm?(message, default: false)
      return default unless $stdin.tty?

      suffix = default ? "[Y/n]" : "[y/N]"
      print "#{message} #{suffix}: "

      response = $stdin.gets&.strip&.downcase
      return default if response.nil? || response.empty?

      %w[y yes].include?(response)
    end

    # Print a mode banner
    # @param mode [String] Mode name
    # @param details [Hash] Mode details
    def print_mode_banner(mode, details = {})
      return if quiet?

      puts
      puts pastel.cyan.bold("═" * 50)
      puts pastel.cyan.bold("  #{mode}")
      puts pastel.cyan.bold("═" * 50)
      puts

      details.each do |key, value|
        print_info(key.to_s, value.to_s)
      end
      puts
    end
  end

  # Null spinner for quiet mode (does nothing)
  class NullSpinner
    def auto_spin; end
    def success(_msg = nil); end
    def error(_msg = nil); end
    def stop; end
    def update(**_options); end
  end

  # Null progress bar for quiet mode (does nothing)
  class NullProgressBar
    def advance(_count = 1); end
    def finish; end
    def current=(_value); end
    def start; end
    def stop; end
  end
end
