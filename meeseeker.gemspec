# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'meeseeker/version'

Gem::Specification.new do |s|
  s.name = 'meeseeker'
  s.version = Meeseeker::VERSION
  s.licenses = 'CC0-1.0'
  s.summary = 'Redis based block follower is an efficient way for multiple apps to stream the Steem Blockchain.'
  s.description = 'If you have multiple applications that need to perform actions as operations occur, `meeseeker` will allow your apps to each perform actions for specific operations without each app having to streaming the entire blockchain.'
  s.authors = ['Anthony Martin']
  s.email = ['meeseeker@martin-studio.com,']
  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test)/}) }
  s.homepage = 'https://rubygems.org/gems/meeseeker'
  s.metadata = { 'source_code_uri' => 'https://github.com/inertia186/meeseeker' }
  s.bindir = 'bin'
  s.executables = 'meeseeker'

  # Ruby Make (interprets the Rakefile DSL).
  s.add_development_dependency 'rake', '~> 12.3', '>= 12.3.1'

  s.add_dependency 'redis', '~> 4.1', '>= 4.1.0'
  s.add_dependency 'steem-mechanize', '~> 0.0', '>= 0.0.5'
  s.add_dependency 'rb-readline', '~> 0.5', '>= 0.5.5'
end
