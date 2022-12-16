require "bundler/gem_tasks"
require 'rspec/core'
require 'rspec/core/rake_task'
require_relative './lib/wp2txt/version.rb'
class String
  def strip_heredoc
    gsub(/^#{scan(/^[ \t]*(?=\S)/).min}/, ''.freeze)
  end
end

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => :spec

desc 'Push Docker images'
task :push do
  sh <<-EOS.strip_heredoc, {verbose: false}
    /bin/bash -xeu <<'BASH'
      # docker buildx create --name mybuilder
      # docker buildx use mybuilder
      # docker buildx inspect --bootstrap
      docker buildx build --platform linux/amd64,linux/arm64 -t yohasebe/wp2txt:#{Wp2txt::VERSION} -t yohasebe/wp2txt:latest . --push
    BASH
  EOS
end
