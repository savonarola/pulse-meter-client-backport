require 'rubygems'
require 'bundler/setup'
$:.unshift File.expand_path('../../lib/', __FILE__)

ROOT = File.expand_path('../..', __FILE__)

Bundler.require(:default, :test, :development)

require 'pulse-meter'
require 'rack/test'

Dir['spec/support/**/*.rb'].each{|f| require File.join(ROOT, f) }
Dir['spec/shared_examples/**/*.rb'].each{|f| require File.join(ROOT,f)}

RSpec.configure do |config|
  config.before(:each) { PulseMeter.redis = MockRedis.new }
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
  config.include(Matchers)
end

