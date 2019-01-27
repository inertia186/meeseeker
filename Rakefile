require "bundler/gem_tasks"
require "rake/testtask"
require 'meeseeker'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.ruby_opts << if ENV['HELL_ENABLED']
    '-W2'
  else
    '-W1'
  end
end

task :default => :test

task :console do
  exec "irb -r meeseeker -I ./lib"
end

desc 'Build a new version of the meeseeker gem.'
task :build do
  exec 'gem build meeseeker.gemspec'
end

desc 'Publish the current version of the meeseeker gem.'
task :push do
  exec "gem push meeseeker-#{Meeseeker::VERSION}.gem"
end

task :check_schema do
  begin
    abort 'Unable to ping redis source.' unless Meeseeker.redis.ping == 'PONG'
  rescue Redis::CommandError => e
    puts e
  rescue Redis::CannotConnectError => e
    puts e
  end
end

task(:sync, [:at_block_num] => [:check_schema]) do |t, args|
  job = Meeseeker::BlockFollowerJob.new
  job.perform(at_block_num: args[:at_block_num])
end

task(:find, [:what, :key] => [:check_schema]) do |t, args|
  redis = Meeseeker.redis
  match = case args[:what].downcase.to_sym
  when :block then "steem:#{args[:key]}:*"
  when :trx then "steem:*:#{args[:key]}:*"
  else; abort "Unknown lookup using #{args}"
  end

  puts "Looking for match on: #{match}"
  keys = redis.keys(match)
  
  keys.each do |key|
    puts key
    puts redis.get(key)
  end
end

task reset: [:check_schema] do
  print 'Dropping keys ...'
  keys = Meeseeker.redis.keys('steem:*')
  
  if keys.any?
    print " found #{keys.size} keys ..."
    dropped = Meeseeker.redis.del(*keys)
    puts " dropped #{dropped} keys."
  else
    puts ' nothing to drop.'
  end
end
