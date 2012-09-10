[![Build Status](https://secure.travis-ci.org/savonarola/pulse-meter-client-backport.png)]
(http://travis-ci.org/savonarola/pulse-meter-client-backport)

# PulseMeter

PulseMeter is a gem for fast and convenient realtime aggregating of software internal stats through Redis.
This is a client part of it backported for ruby 1.8.x. It allows to create sensors and send data to them, but
neither reduce nor visualize.

It is supposed to use a standalone newer installation of ruby to perform reducing and visualisation.

## Client usage

Just create sensor objects and write data. Some examples below.

    require 'pulse-meter'
    PulseMeter.redis = Redis.new

    # static sensor examples

    counter = PulseMeter::Sensor::Counter.new :my_counter
    counter.event(1)
    counter.event(2)
    puts counter.value
    # prints
    # 3

    indicator = PulseMeter::Sensor::Indicator.new :my_value
    indicator.event(3.14)
    indicator.event(2.71)
    puts indicator.value
    # prints
    # 2.71

    hashed_counter = PulseMeter::Sensor::HashedCounter.new :my_h_counter
    hashed_counter.event(:x => 1)
    hashed_counter.event(:y => 5)
    hashed_counter.event(:y => 1)
    p hashed_counter.value
    # prints
    # {"x"=>1, "y"=>6}

    # timeline sensor examples

    requests_per_minute = PulseMeter::Sensor::Timelined::Counter.new(:my_t_counter,
      :interval => 60,         # count for each minute
      :ttl => 24 * 60 * 60     # keep data one day
    )
    requests_per_minute.event(1)
    requests_per_minute.event(1)
    sleep(60)
    requests_per_minute.event(1)
    requests_per_minute.timeline(2 * 60).each do |v|
      puts "#{v.start_time}: #{v.value}"
    end
    # prints somewhat like
    # 2012-05-24 11:06:00 +0400: 2
    # 2012-05-24 11:07:00 +0400: 1

    max_per_minute = PulseMeter::Sensor::Timelined::Max.new(:my_t_max,
      :interval => 60,         # max for each minute
      :ttl => 24 * 60 * 60     # keep data one day
    )
    max_per_minute.event(3)
    max_per_minute.event(1)
    max_per_minute.event(2)
    sleep(60)
    max_per_minute.event(5)
    max_per_minute.event(7)
    max_per_minute.event(6)
    max_per_minute.timeline(2 * 60).each do |v|
      puts "#{v.start_time}: #{v.value}"
    end
    # prints somewhat like
    # 2012-05-24 11:07:00 +0400: 3.0
    # 2012-05-24 11:08:00 +0400: 7.0

## Installation

Add this line to your application's Gemfile:

    gem 'pulse-meter-client-backport'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pulse-meter-client-backport

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

