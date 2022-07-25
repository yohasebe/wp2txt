 # -*- coding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "wp2txt/version"

Gem::Specification.new do |s|
  s.name        = "wp2txt"
  s.version     = Wp2txt::VERSION
  s.authors     = ["Yoichiro Hasebe"]
  s.email       = ["yohasebe@gmail.com"]
  s.homepage    = "http://github.com/yohasebe/wp2txt"
  s.summary     = %q{Wikipedia dump to text converter}
  s.description = %q{WP2TXT extracts plain text data from Wikipedia dump file (encoded in XML/compressed with Bzip2) stripping all the MediaWiki markups and other metadata.}

  s.rubyforge_project = "wp2txt"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # s.add_development_dependency "bundler"
  # s.add_development_dependency "rspec"
  # s.add_development_dependency "rake"

  s.add_dependency "nokogiri"
  s.add_dependency "parallel"
  s.add_dependency "htmlentities"
  s.add_dependency "optimist"
end
