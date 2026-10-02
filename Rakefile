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
# it for names, content, and modes that must never ship.
Rake::Task["build"].enhance { sh "ruby", "scripts/verify_gem.rb" }

# =============================================================================
# Docker
# =============================================================================

desc "Build the image from a clean copy of the last commit and run the gate CI runs"
task :check_image do
  # A clean clone is what CI builds from: files that exist only in this working
  # tree never reach the context, and the gate compares the image against it.
  require "tmpdir"
  Dir.mktmpdir("wp2txt-image-") do |dir|
    sh "git", "clone", "--quiet", "--no-local", ".", dir
    sh "docker", "build", "-t", "wp2txt-verify:local", dir
    sh "ruby", "scripts/verify_image.rb", "wp2txt-verify:local", "--context", dir
  end
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
