# frozen_string_literal: true

require_relative "lib/wp2txt/version"

Gem::Specification.new do |s|
  s.name        = "wp2txt"
  s.version     = Wp2txt::VERSION
  s.authors     = ["Yoichiro Hasebe"]
  s.email       = ["yohasebe@gmail.com"]
  s.homepage    = "https://github.com/yohasebe/wp2txt"
  s.summary     = "A command-line toolkit to extract text content and category data from Wikipedia dump files"
  s.description = "WP2TXT extracts text and category data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing MediaWiki markup and other metadata."
  s.rubyforge_project = "wp2txt"
  s.license = "MIT"
  s.required_ruby_version = Gem::Requirement.new(">= 2.6")
  s.files = `git ls-files`.split("\n")
  s.files -= ["data/*", "image/*"]
  s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_development_dependency "bundler"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_dependency "htmlentities"
  s.add_dependency "nokogiri"
  s.add_dependency "optimist"
  s.add_dependency "parallel"
  s.add_dependency "pastel"
  s.add_dependency "ruby-progressbar"
  s.add_dependency "tty-spinner"
end
