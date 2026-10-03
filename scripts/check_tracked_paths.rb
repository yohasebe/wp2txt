#!/usr/bin/env ruby
# frozen_string_literal: true

# Tracked-path allow list: every file git tracks must match a line of
# scripts/tracked_paths.allow, and every line there must match a tracked file.
#
# The gem is built from `git ls-files` and the image from a clean checkout, so
# a file that gets committed is already on its way to being published. Lists
# of forbidden names only stop the kinds someone thought of; this check works
# the other way round, and anything that is not an expected kind of file in an
# expected place fails.
#
# Usage:
#   ruby scripts/check_tracked_paths.rb             # the index (next commit)
#   ruby scripts/check_tracked_paths.rb --tree REV  # a commit (e.g. before a push)
#
# The allow list is read from the same place as the files: the index, or the
# commit given to --tree. An unstaged edit to the list changes nothing until
# it is staged.
#
# Braces are expanded before matching, and each alternative must match a
# tracked file, so `{rb,json}` cannot keep an unused `json` alive.
#
# Output is paths only. Exits 1 on any unallowed path, unused alternative, or
# when the files or the list cannot be read (outside a checkout nothing is
# "clean"; --tree without a revision is an error, not the index).

ROOT = File.expand_path("..", __dir__)
ALLOW_PATH = "scripts/tracked_paths.allow"
# FNM_PATHNAME keeps `*` within one directory; `**/` spans any depth.
FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

def git_read(*args)
  out = IO.popen(["git", "-C", ROOT, *args], err: File::NULL, &:read)
  $?.success? ? out : nil
rescue SystemCallError
  nil
end

# "a/{b,c}/*.{x,y}" -> ["a/b/*.x", "a/b/*.y", "a/c/*.x", "a/c/*.y"]. Braces do
# not nest, and an empty alternative ("README{,_ja}.md") is kept.
def expand_braces(pattern)
  open_at = pattern.index("{")
  return [pattern] unless open_at

  close_at = pattern.index("}", open_at) or abort("[tracked_paths] unbalanced brace: #{pattern}")
  head = pattern[0...open_at]
  tail = pattern[(close_at + 1)..]
  pattern[(open_at + 1)...close_at].split(",", -1).flat_map { |alt| expand_braces("#{head}#{alt}#{tail}") }
end

if ARGV.include?("--tree")
  tree = ARGV[ARGV.index("--tree") + 1]
  if tree.nil? || tree.start_with?("-")
    puts "[tracked_paths] --tree needs a revision; refusing to pass."
    exit 1
  end
end

source = tree || "the index"
listing = tree ? git_read("ls-tree", "-r", "-z", "--name-only", tree) : git_read("ls-files", "-z")
allow = git_read("show", "#{tree}:#{ALLOW_PATH}")
files = listing&.split("\0")

if files.nil? || files.empty?
  puts "[tracked_paths] could not list tracked files in #{source}; refusing to pass."
  exit 1
end
if allow.nil?
  puts "[tracked_paths] #{source} has no #{ALLOW_PATH}; refusing to pass."
  exit 1
end

lines = allow.lines(chomp: true).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
alternatives = lines.flat_map { |line| expand_braces(line).map { |alt| [line, alt] } }
used = Array.new(alternatives.size, false)
unallowed = files.reject do |path|
  hits = alternatives.each_index.select { |i| File.fnmatch?(alternatives[i][1], path, FLAGS) }
  hits.each { |i| used[i] = true }
  hits.any?
end
unused = alternatives.each_index.reject { |i| used[i] }.map { |i| alternatives[i] }

puts "[tracked_paths] checked #{files.size} tracked file(s) in #{source} against #{lines.size} line(s)"
if unallowed.empty? && unused.empty?
  puts "[tracked_paths] OK: every tracked file is allowed and every alternative is in use."
  exit 0
end

unless unallowed.empty?
  puts "[tracked_paths] #{unallowed.size} tracked file(s) not in #{ALLOW_PATH}:"
  unallowed.each { |path| puts "  #{path}" }
end
unless unused.empty?
  puts "[tracked_paths] #{unused.size} alternative(s) match no tracked file (remove or narrow them):"
  unused.each { |line, alt| puts(line == alt ? "  #{line}" : "  #{alt}  (from #{line})") }
end
puts ""
puts "If a new file belongs in the repository, add the narrowest line that"
puts "describes its place and kind, and stage the list. If it does not,"
puts "untrack it (git rm --cached)."
exit 1
