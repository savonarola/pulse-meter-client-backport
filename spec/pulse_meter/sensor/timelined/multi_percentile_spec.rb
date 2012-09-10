require 'spec_helper'

describe PulseMeter::Sensor::Timelined::MultiPercentile do
  it_should_behave_like "timeline sensor", {:p => [0.8]}
  
  let(:name){ :counter }
  let(:ttl){ 100 }
  let(:raw_data_ttl){ 10 }
  let(:interval){ 5 }
  let(:reduce_delay){ 3 }
  let(:init_values){ {:ttl => ttl, :raw_data_ttl => raw_data_ttl, :interval => interval, :reduce_delay => reduce_delay, :p => [0.8, 0.5] }}
  let(:sensor){ described_class.new(name, init_values) }
  let(:epsilon) {1}

  it "should calculate summarized value" do
    events = [5, 4, 2, 2, 2, 2, 2, 2, 2, 1]
    interval_id = 0
    start_of_interval = Time.at(interval_id)
    Timecop.freeze(start_of_interval) do
      events.each {|e| sensor.event(e)}
    end
    Timecop.freeze(start_of_interval + interval) do
      data = sensor.timeline(interval + epsilon).first
      hash = JSON.parse(data.value)
      hash.each { |k, v| hash[k] = v.to_f }
      hash.should == {"0.8" => 2.0, "0.5" => 2.0}
    end
  end

  it "should raise exception when extra parameter is not array of percentiles" do
    expect {described_class.new(name, init_values.merge({:p => :bad}))}.to raise_exception(ArgumentError) 
  end

  it "should raise exception when one of percentiles is not between 0 and 1" do
    expect {described_class.new(name, init_values.merge({:p => [0.5, -1]}))}.to raise_exception(ArgumentError) 
    expect {described_class.new(name, init_values.merge({:p => [0.5, 1.1]}))}.to raise_exception(ArgumentError) 
    expect {described_class.new(name, init_values.merge({:p => [0.5, 0.1]}))}.not_to raise_exception(ArgumentError) 
  end

end
