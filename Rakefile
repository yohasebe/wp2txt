# frozen_string_literal: true

require "bundler/gem_tasks"
require "open3"
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

# Pre-release gate: verify the built gem's payload against spec.files and scan
# it for names, content, and modes that must never ship (code-security protocol).
Rake::Task["build"].enhance { sh "ruby", "scripts/verify_gem.rb" }

# =============================================================================
# Docker
# =============================================================================

# Paths that must never reach a published image. The image is built from the
# working tree, so anything ignored locally (private notes, scratch files)
# would otherwise ride along.
IMAGE_FORBIDDEN_PATHS = %w[/wp2txt/research-notes /wp2txt/tmp /wp2txt/.git /wp2txt/CLAUDE.md /wp2txt/.claude /wp2txt/.private-doc-tokens].freeze

desc "Verify a built image contains no private material (run before pushing)"
task :verify_image, [:tag] do |_t, args|
  tag = args[:tag] || "wp2txt-verify:local"
  checks = IMAGE_FORBIDDEN_PATHS.map { |p| "test -e #{p} && echo LEAK:#{p}" }.join("; ")
  out, status = Open3.capture2e("docker", "run", "--rm", tag, "sh", "-c", "#{checks}; true")
  abort "Image verification failed for #{tag}: #{out}" unless status.success?
  leaks = out.lines.grep(/^LEAK:/).map(&:strip)
  abort "Image #{tag} contains private paths:\n  #{leaks.join("\n  ")}" unless leaks.empty?

  puts "OK: #{tag} contains none of #{IMAGE_FORBIDDEN_PATHS.join(', ')}"
end

desc "Build the image locally and verify it, without pushing"
task :check_image do
  sh "docker build -t wp2txt-verify:local ."
  Rake::Task[:verify_image].invoke
end

desc "Explain how images are published (they are built and pushed by CI)"
task :push do
  abort <<~MESSAGE
    Images are published by GitHub Actions, not from here.

    A local build sends this working tree as the build context, so untracked
    files ride along; a runner starts from a clean checkout, where they do not
    exist. Push a v* tag and .github/workflows/publish-image.yml takes over:

        rake release            # tags and pushes (also publishes the gem)

    To rehearse without publishing, run the workflow from the Actions tab with
    "push" left off. To check a local build, run `rake check_image`.
  MESSAGE
end
