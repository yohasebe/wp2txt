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

# Gem packaging preserves on-disk file modes; owner-only permissions here
# produce gems whose files are unreadable after a sudo install.
task :normalize_permissions do
  `git ls-files -z`.split("\x0").each do |f|
    executable = File.executable?(f) || f.start_with?("bin/", "exe/")
    File.chmod(executable ? 0o755 : 0o644, f)
  end
end

Rake::Task["build"].enhance([:normalize_permissions])

# =============================================================================
# Docker
# =============================================================================

# Paths that must never reach a published image. The image is built from the
# working tree, so anything ignored locally (private notes, scratch files)
# would otherwise ride along.
IMAGE_FORBIDDEN_PATHS = %w[/wp2txt/research-notes /wp2txt/tmp /wp2txt/.git /wp2txt/CLAUDE.md /wp2txt/.claude].freeze

desc "Verify a built image contains no private material (run before pushing)"
task :verify_image, [:tag] do |_t, args|
  tag = args[:tag] || "wp2txt-verify:local"
  checks = IMAGE_FORBIDDEN_PATHS.map { |p| "test -e #{p} && echo LEAK:#{p}" }.join("; ")
  out = `docker run --rm #{tag} sh -c '#{checks}; true' 2>&1`
  leaks = out.lines.grep(/^LEAK:/).map(&:strip)
  abort "Image #{tag} contains private paths:\n  #{leaks.join("\n  ")}" unless leaks.empty?

  puts "OK: #{tag} contains none of #{IMAGE_FORBIDDEN_PATHS.join(', ')}"
end

desc "Build the image locally and verify it, without pushing"
task :check_image do
  sh "docker build -t wp2txt-verify:local ."
  Rake::Task[:verify_image].invoke
end

desc "Build and push Docker images to GHCR (verifies a local build first)"
task push: :check_image do
  # Docker Hub was retired after 2.3.0; GHCR (ghcr.io/yohasebe/wp2txt) is the
  # only registry. Requires `docker buildx use multiarch` and a ghcr.io login.
  sh <<-SCRIPT.strip_heredoc, { verbose: false }
    /bin/bash -xeu <<'BASH'
      # docker buildx create --name multiarch
      # docker buildx use multiarch
      # docker buildx inspect --bootstrap
      docker buildx build --platform linux/amd64,linux/arm64 \
        -t ghcr.io/yohasebe/wp2txt:#{Wp2txt::VERSION} -t ghcr.io/yohasebe/wp2txt:latest \
        . --push
    BASH
  SCRIPT
end
