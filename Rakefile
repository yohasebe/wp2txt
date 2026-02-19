# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core"
require "rspec/core/rake_task"
require_relative "./lib/wp2txt/version"

class String
  def strip_heredoc
    gsub(/^#{scan(/^[ \t]*(?=\S)/).min}/, "")
  end
end

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList["spec/**/*_spec.rb"]
end

task default: :spec

# =============================================================================
# Docker
# =============================================================================

desc "Push Docker images"
task :push do
  sh <<-SCRIPT.strip_heredoc, { verbose: false }
    /bin/bash -xeu <<'BASH'
      # docker buildx create --name mybuilder
      # docker buildx use mybuilder
      # docker buildx inspect --bootstrap
      docker buildx build --platform linux/amd64,linux/arm64 -t yohasebe/wp2txt:#{Wp2txt::VERSION} -t yohasebe/wp2txt:latest . --push
    BASH
  SCRIPT
end
