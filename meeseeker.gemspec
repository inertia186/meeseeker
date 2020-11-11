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
  s.files = Dir['bin/**/*', 'lib/**/*', 'test/**/*', 'Gemfile', 'LICENSE', 'Rakefile', 'README.md', 'meeseeker.gemspec']
  s.test_files = Dir['test/**/*']
  s.executables = Dir['bin/*'].map{ |f| File.basename(f) }
  s.homepage = 'https://rubygems.org/gems/meeseeker'
  s.metadata = { 'source_code_uri' => 'https://github.com/inertia186/meeseeker' }
  s.bindir = 'bin'
  s.executables = 'meeseeker'

  # Ruby Make (interprets the Rakefile DSL).
  s.add_development_dependency 'rake', '~> 12.3', '>= 12.3.1'
  s.add_development_dependency 'minitest', '~> 5.10', '>= 5.10.3'
  s.add_development_dependency 'minitest-line', '~> 0.6', '>= 0.6.4'
  s.add_development_dependency 'minitest-proveit', '~> 1.0', '>= 1.0.0'
  s.add_development_dependency 'simplecov', '~> 0.15', '>= 0.15.1'
  s.add_development_dependency 'pry', '~> 0.11', '>= 0.11.3'
  s.add_development_dependency 'irb', '~> 1.0', '>= 1.0.0'
  s.add_development_dependency 'mock_redis', '~> 0.22', '>= 0.22.0'

  s.add_dependency 'redis', '~> 4.1', '>= 4.1.0'
  s.add_dependency 'radiator', '~> 0.4', '>= 0.4.8'
  s.add_dependency 'mechanize', '~> 2.7', '>= 2.7.6'
  s.add_dependency 'rb-readline', '~> 0.5', '>= 0.5.5'
end
