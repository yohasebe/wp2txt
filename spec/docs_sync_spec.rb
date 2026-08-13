# frozen_string_literal: true

require "spec_helper"

# The MCP tool surface and its public documentation drift apart easily
# (the 2.2.0 README shipped with a tool table missing four tools). This spec
# pins them together: every tool defined in bin/wp2txt-mcp must appear in the
# docs/INDEXES.md tool table, and the table must not list phantom tools.
RSpec.describe "documentation surface sync" do
  repo_root = File.expand_path("..", __dir__)

  define_method(:defined_tools) do
    src = File.read(File.join(repo_root, "bin", "wp2txt-mcp"))
    src.scan(/server\.define_tool\(\s*name:\s*"([a-z_]+)"/).flatten
  end

  define_method(:documented_tools) do
    doc = File.read(File.join(repo_root, "docs", "INDEXES.md"))
    table = doc[/^### Tools\n(.*?)\n\n/m, 1]
    raise "Tools table not found in docs/INDEXES.md" unless table

    # Tool names live in the first column only (the purpose column may
    # backtick argument names like `attach`)
    table.lines.filter_map { |line| line.split("|")[1] }
         .flat_map { |cell| cell.scan(/`([a-z_]+)`/).flatten }
         .uniq
  end

  it "defines a non-trivial number of MCP tools" do
    expect(defined_tools.size).to be >= 15
  end

  it "documents every MCP tool in docs/INDEXES.md, with no phantom entries" do
    missing = defined_tools - documented_tools
    phantom = documented_tools - defined_tools
    expect(missing).to be_empty, "tools not documented in docs/INDEXES.md: #{missing.join(', ')}"
    expect(phantom).to be_empty, "documented tools that do not exist: #{phantom.join(', ')}"
  end

  # Tripwire: tracked files must not contain tokens listed in .private-doc-tokens,
  # an untracked, machine-local file (one substring per line; # starts a comment).
  # The file exists only on machines that maintain such a list; everywhere else
  # (CI, other contributors) this example skips — loudly, so a silently dead
  # check cannot be mistaken for a passing one.
  it "keeps machine-local private tokens out of tracked files" do
    token_file = File.join(repo_root, ".private-doc-tokens")
    skip "SKIPPED: no .private-doc-tokens on this machine — tripwire not checked" unless File.exist?(token_file)

    tokens = File.readlines(token_file, encoding: "UTF-8")
                 .map(&:strip).reject { |t| t.empty? || t.start_with?("#") }
    tracked = `git -C #{repo_root} ls-files -z`.split("\x0")
    hits = tracked.flat_map do |f|
      path = File.join(repo_root, f)
      next [] unless File.file?(path)

      content = File.read(path, encoding: "BINARY")
      tokens.filter_map { |t| "#{f}: #{t}" if content.include?(t.b) }
    end
    expect(hits).to be_empty, "private tokens found in tracked files:\n  #{hits.join("\n  ")}"
  end
end
