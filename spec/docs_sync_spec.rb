# frozen_string_literal: true

require "spec_helper"

# The MCP tool surface and its public documentation drift apart easily
# (the 2.2.0 README shipped with a tool table missing four tools). This spec
# pins them together: every tool defined in bin/wp2txt-mcp must appear in the
# docs/RESEARCH.md tool table, and the table must not list phantom tools.
RSpec.describe "documentation surface sync" do
  repo_root = File.expand_path("..", __dir__)

  define_method(:defined_tools) do
    src = File.read(File.join(repo_root, "bin", "wp2txt-mcp"))
    src.scan(/server\.define_tool\(\s*name:\s*"([a-z_]+)"/).flatten
  end

  define_method(:documented_tools) do
    doc = File.read(File.join(repo_root, "docs", "RESEARCH.md"))
    table = doc[/^### Tools\n(.*?)\n\n/m, 1]
    raise "Tools table not found in docs/RESEARCH.md" unless table

    # Tool names live in the first column only (the purpose column may
    # backtick argument names like `attach`)
    table.lines.filter_map { |line| line.split("|")[1] }
         .flat_map { |cell| cell.scan(/`([a-z_]+)`/).flatten }
         .uniq
  end

  it "defines a non-trivial number of MCP tools" do
    expect(defined_tools.size).to be >= 15
  end

  it "documents every MCP tool in docs/RESEARCH.md, with no phantom entries" do
    missing = defined_tools - documented_tools
    phantom = documented_tools - defined_tools
    expect(missing).to be_empty, "tools not documented in docs/RESEARCH.md: #{missing.join(', ')}"
    expect(phantom).to be_empty, "documented tools that do not exist: #{phantom.join(', ')}"
  end
end
