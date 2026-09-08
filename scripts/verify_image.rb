#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_image.rb — pre-publish gate for the container image
#
# Measures instead of reasoning. It lists what the built image actually holds
# under /wp2txt and compares that against what Docker actually sends as the
# build context. The .dockerignore rules are never reimplemented here: Docker
# is asked what the context contains, so the gate and the builder cannot drift
# apart the way two copies of one rule always do.
#
# Three sets, and every difference between them has to be accounted for:
#
#   tracked (git ls-files)  ⊇  context (what Docker sends)  →  image payload
#
#   1. context - tracked  must be empty. A file in the context that git does
#      not track is precisely how private material reached published images
#      twice: it sits in the working tree, .gitignore keeps it out of commits,
#      and `COPY . ./` ships it regardless. This is empty by construction on a
#      CI checkout; it earns its keep when someone builds from a working tree.
#   2. image - context    must equal BUILD_ARTIFACTS exactly.
#   3. context - image    must be empty (catches a .dockerignore entry that
#      drops something the image needs).
#
# A private file that was committed is tracked, so it sits in all three sets
# and no comparison can see it. Names and contents of the payload are matched
# against patterns that must never ship, and the image's environment and build
# history are scanned for secrets passed in through ARG or ENV.
#
# An empty payload fails: a check that inspects nothing must not pass.
#
#   ruby scripts/verify_image.rb <image-ref> [--context DIR]
#
# Control tests (run when adopting, and again whenever this file changes):
#   1. leave an untracked file in the working tree, build, run → must FAIL
#   2. remove an entry from BUILD_ARTIFACTS, run → that file must FAIL as unknown
#   3. clean checkout → must PASS

require "json"
require "open3"
require "tmpdir"
require "fileutils"

# Files the build creates. Anything else appearing in the image but not in the
# context is unexplained and fails the gate.
#
#   Gemfile.lock — the Dockerfile deletes the copied one and `bundle install`
#                  resolves a fresh one against the image's Ruby.
BUILD_ARTIFACTS = ["Gemfile.lock"].freeze

# Where the repository content lives inside the image (WORKDIR in the Dockerfile).
PAYLOAD_ROOT = "wp2txt/"

BAD_NAMES = [
  %r{(\A|/)[^/]*\.env(\.[^/]*)?\z}, %r{(\A|/)\.envrc\z},
  %r{(\A|/)(CLAUDE|AGENTS|GEMINI)\.md\z}, %r{(\A|/)\.claude/},
  %r{(\A|/)(credentials|secrets?)[^/]*\z}i, %r{(\A|/)id_(rsa|ed25519|ecdsa)[^/]*\z},
  %r{(\A|/)\.DS_Store\z}, %r{\.(pem|p12|pfx|key|token|log|bak|orig|swp)\z},
  %r{(\A|/)(tmp|pkg|node_modules|__pycache__)/}, %r{(\A|/)\.git/}
].freeze

# Narrow patterns only; broad words like "token" are noise. Patterns whose own
# source text would match are built from adjacent string literals (Ruby joins
# them), so this file never trips its own scan.
SECRET_PATTERNS = {
  "GitHub token" => /\bghp_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b/,
  "OpenAI-style key" => /\bsk-[A-Za-z0-9_-]{20,}\b/,
  "AWS access key" => /\bAKIA[0-9A-Z]{16}\b/,
  "Google API key" => /\bAIza[0-9A-Za-z_-]{35}\b/,
  "Slack token" => /\bxox[baprs]-[0-9A-Za-z-]{10,}\b/,
  "private key block" => Regexp.new("-----BEGIN [A-Z ]*PRIVATE " "KEY-----"),
  "home directory path" => Regexp.new("(?<![A-Za-z0-9_])/(Users|home)/" "[A-Za-z0-9_.-]+/"),
  "Dropbox path" => Regexp.new("/CloudStorage/" "Dropbox/")
}.freeze

context_dir = "."
image = nil
args = ARGV.dup
until args.empty?
  arg = args.shift
  if arg == "--context"
    context_dir = args.shift or abort "verify_image: --context needs a directory"
  else
    image = arg
  end
end
abort "verify_image: usage: verify_image.rb <image-ref> [--context DIR]" unless image

def capture!(*cmd, what:)
  out, err, status = Open3.capture3(*cmd)
  abort "verify_image: could not #{what}: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?
  out
end

# --- the three sets -----------------------------------------------------------

tracked = capture!("git", "-C", context_dir, "ls-files", "-z", what: "list tracked files")
          .split("\0").reject(&:empty?).sort.uniq

# Ask Docker what the context is, rather than reimplementing .dockerignore.
context = Dir.mktmpdir("verify-image-") do |dir|
  dockerfile = File.join(dir, "context.Dockerfile")
  File.write(dockerfile, "FROM scratch\nCOPY . /\n")
  dest = File.join(dir, "out")
  capture!("docker", "buildx", "build", "-f", dockerfile,
           "--output", "type=local,dest=#{dest}", context_dir,
           what: "extract the build context (is buildx available?)")
  Dir.glob(File.join(dest, "**", "*"), File::FNM_DOTMATCH)
     .select { |path| File.file?(path) }
     .map { |path| path.delete_prefix("#{dest}/") }
end.sort.uniq

container = capture!("docker", "create", image, what: "create a container from #{image}").strip
payload = []
payload_dir = Dir.mktmpdir("verify-image-payload-")
begin
  listing = capture!("sh", "-c", "docker export #{container} | tar -tf -", what: "export #{image}")
  payload = listing.lines(chomp: true)
                   .select { |name| name.start_with?(PAYLOAD_ROOT) }
                   .reject { |name| name.end_with?("/") }
                   .map { |name| name.delete_prefix(PAYLOAD_ROOT) }
                   .sort.uniq
  capture!("docker", "cp", "#{container}:/#{PAYLOAD_ROOT.chomp('/')}", payload_dir,
           what: "copy the payload out of #{image}")
ensure
  system("docker", "rm", container, out: File::NULL, err: File::NULL)
end

failures = []

# --- 0. must inspect something -------------------------------------------------

failures << "image payload is empty — nothing was inspected" if payload.empty?
failures << "build context is empty — nothing to compare against" if context.empty?

# --- 1..3. the three comparisons -----------------------------------------------

untracked_in_context = context - tracked
unless untracked_in_context.empty?
  failures << "files in the build context that git does not track (#{untracked_in_context.size}) — " \
              "this is how private files reach published images:\n  " + untracked_in_context.join("\n  ")
end

unexplained = payload - context - BUILD_ARTIFACTS
unless unexplained.empty?
  failures << "files in the image that the context does not explain (#{unexplained.size}) — " \
              "if the build creates them on purpose, add them to BUILD_ARTIFACTS:\n  " + unexplained.join("\n  ")
end

absent_artifacts = BUILD_ARTIFACTS - payload
unless absent_artifacts.empty?
  failures << "declared build artifacts missing from the image (#{absent_artifacts.size}) — " \
              "the build changed; re-derive BUILD_ARTIFACTS:\n  " + absent_artifacts.join("\n  ")
end

dropped = context - payload
unless dropped.empty?
  failures << "files sent in the context but absent from the image (#{dropped.size}) — " \
              "check .dockerignore and the Dockerfile:\n  " + dropped.join("\n  ")
end

# --- 4. names that must never ship ---------------------------------------------

bad = payload.select { |name| BAD_NAMES.any? { |re| name.match?(re) } }
failures << "payload names that must never ship (#{bad.size}):\n  " + bad.join("\n  ") unless bad.empty?

# --- 5. payload contents --------------------------------------------------------

hits = []
Dir.glob(File.join(payload_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
  next unless File.file?(path)
  next if File.size(path) > 4_000_000

  data = File.binread(path)
  name = path.delete_prefix("#{payload_dir}/")
  SECRET_PATTERNS.each { |label, re| hits << "#{name}: #{label}" if data.match?(re) }
end
failures << "secrets or local paths in the payload (#{hits.size}):\n  " + hits.join("\n  ") unless hits.empty?
FileUtils.remove_entry(payload_dir)

# --- 6. environment and build history -------------------------------------------

env = JSON.parse(capture!("docker", "image", "inspect", "--format", "{{json .Config.Env}}", image,
                          what: "inspect the environment of #{image}"))
env_hits = Array(env).flat_map do |entry|
  SECRET_PATTERNS.filter_map { |label, re| "#{entry.split('=').first}: #{label}" if entry.match?(re) }
end
failures << "secrets in the image environment (#{env_hits.size}):\n  " + env_hits.join("\n  ") unless env_hits.empty?

history = capture!("docker", "history", "--no-trunc", "--format", "{{.CreatedBy}}", image,
                   what: "read the build history of #{image}")
history_hits = history.lines(chomp: true).flat_map do |line|
  SECRET_PATTERNS.filter_map { |label, re| "#{label} in: #{line[0, 120]}" if line.match?(re) }
end
unless history_hits.empty?
  failures << "secrets in the build history — passed through ARG or ENV (#{history_hits.size}):\n  " +
              history_hits.join("\n  ")
end

# --- report ----------------------------------------------------------------------

if failures.empty?
  puts "verify_image: PASS — #{image}: #{payload.size} files under /#{PAYLOAD_ROOT} " \
       "(#{context.size} from the context, #{BUILD_ARTIFACTS.size} built); " \
       "every context file is tracked; no forbidden names, secrets, or local paths"
  exit 0
else
  warn "verify_image: FAIL — #{image}"
  failures.each { |failure| warn "  * #{failure}" }
  exit 1
end
