# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

# scripts/check_tracked_paths.rb and scripts/pre-push, run against a disposable
# copy of this repository's index: what it passes, and what it must stop.
RSpec.describe "tracked-path allow list" do
  repo_root = File.expand_path("..", __dir__)

  around do |example|
    Dir.mktmpdir("wp2txt-paths-") do |dir|
      @dir = dir
      @repo = File.join(dir, "repo")
      # Commits in the copy run no hooks but the one under test
      @no_hooks = File.join(dir, "no-hooks")
      Dir.mkdir(@no_hooks)
      Dir.mkdir(@repo)
      system("git", "-C", repo_root, "checkout-index", "-a", "-f", "--prefix=#{@repo}/", exception: true)
      git("init", "-q", "-b", "master")
      git("add", "-A")
      commit("initial")
      example.run
    end
  end

  def git(*args, hooks: @no_hooks)
    out, status = Open3.capture2e("git", "-c", "core.hooksPath=#{hooks}", "-c", "user.name=t",
                                  "-c", "user.email=t@example.invalid", "-C", @repo, *args)
    raise "git #{args.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  def commit(message)
    git("commit", "-q", "--allow-empty", "-m", message)
  end

  def put(path, content = "x\n", stage: true)
    full = File.join(@repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content, mode: "a")
    git("add", path) if stage
  end

  def check(*args)
    out, status = Open3.capture2e(RbConfig.ruby, File.join(@repo, "scripts", "check_tracked_paths.rb"), *args)
    [status.success?, out]
  end

  it "passes the files tracked now" do
    expect(check).to match([true, /OK: every tracked file is allowed/])
  end

  it "stops an internal note, wherever it is placed" do
    ["notes/plan.md", "PLAN.md", "README_plan.md", "docs/PLAN.md", "spec/notes.md"].each do |path|
      put(path)
      ok, out = check
      expect([path, ok]).to eq([path, false])
      expect(out).to include("  #{path}\n")
      git("rm", "-q", "--cached", path)
    end
  end

  it "stops logs, environment files, databases, and data in places not allowed" do
    %w[debug.log .env data.sqlite3 dump.json lib/dump.json lib/wp2txt/data/dump.json spec/fixtures/dump.json].each do |path|
      put(path)
      expect(check.first).to be(false), "#{path} passed"
      git("rm", "-q", "--cached", path)
    end
  end

  it "stops an alternative that matches no tracked file" do
    put("scripts/tracked_paths.allow", "image/*.{svg,png}\n")
    ok, out = check
    expect(ok).to be(false)
    expect(out).to include("image/*.png  (from image/*.{svg,png})")
  end

  it "judges by the staged list, not by an unstaged edit to it" do
    put("notes/plan.md")
    put("scripts/tracked_paths.allow", "notes/*.md\n", stage: false)
    expect(check.first).to be(false)
  end

  it "judges a commit by the list inside that commit" do
    put("notes/plan.md")
    commit("add a note")
    expect(check("--tree", "HEAD").first).to be(false)
    expect(check("--tree", "HEAD~1").first).to be(true)
  end

  it "refuses to pass when it saw nothing" do
    expect(check("--tree")).to match([false, /needs a revision/])
    expect(check("--tree", "--other")).to match([false, /needs a revision/])
    expect(check("--tree", "no-such-rev")).to match([false, /could not list/])
    git("rm", "-q", "--cached", "scripts/tracked_paths.allow")
    expect(check).to match([false, /has no scripts\/tracked_paths.allow/])

    outside = File.join(@dir, "outside", "scripts")
    FileUtils.mkdir_p(outside)
    FileUtils.cp(File.join(@repo, "scripts", "check_tracked_paths.rb"), outside)
    _out, status = Open3.capture2e(RbConfig.ruby, File.join(outside, "check_tracked_paths.rb"))
    expect(status.success?).to be(false)

    system("git", "init", "-q", File.join(@dir, "outside"), exception: true) # a checkout tracking nothing
    out, status = Open3.capture2e(RbConfig.ruby, File.join(outside, "check_tracked_paths.rb"))
    expect([status.success?, out]).to match([false, /could not list/])
  end

  describe "pre-push" do
    before do
      @remote = File.join(@dir, "remote.git")
      system("git", "init", "-q", "--bare", @remote, exception: true)
      git("remote", "add", "origin", @remote)
      git("push", "-q", "origin", "master")
      @hooks = File.join(@dir, "hooks")
      Dir.mkdir(@hooks)
      File.symlink(File.join(@repo, "scripts", "pre-push"), File.join(@hooks, "pre-push"))
    end

    def push
      out, status = Open3.capture2e("git", "-c", "core.hooksPath=#{@hooks}", "-C", @repo, "push", "origin", "master")
      [status.success?, out]
    end

    def remote_head
      `git -C #{@remote} rev-parse master`.strip
    end

    it "lets allowed commits through and says how many it checked" do
      put("lib/wp2txt/extra.rb")
      commit("add a module")
      expect(push).to match([true, /1 commit\(s\) checked/])
    end

    it "stops a push when only a commit in the middle of the range has an unallowed file" do
      before = remote_head
      put("debug.log")
      commit("add a log")
      git("rm", "-q", "debug.log")
      commit("remove it again")
      ok, out = push
      expect(ok).to be(false)
      expect(out).to include("debug.log")
      expect(remote_head).to eq(before)
    end

    it "stops a new commit that carries no allow list" do
      git("rm", "-q", "scripts/tracked_paths.allow")
      commit("drop the list")
      expect(push).to match([false, /without scripts\/tracked_paths.allow/])
    end

    it "checks every commit no remote has when pushing a new branch" do
      git("switch", "-q", "-c", "topic")
      put(".env")
      commit("add env")
      git("rm", "-q", ".env")
      commit("remove env")
      out, status = Open3.capture2e("git", "-c", "core.hooksPath=#{@hooks}", "-C", @repo, "push", "origin", "topic")
      expect(status.success?).to be(false)
      expect(out).to include(".env")
    end
  end
end
