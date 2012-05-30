require 'spec_helper'

describe PulseMeter::Sensor::Timeline do
  let(:name){ :some_value_with_history }
  let(:ttl){ 100 }
  let(:raw_data_ttl){ 10 }
  let(:interval){ 5 }
  let(:reduce_delay){ 3 }
  let(:good_init_values){ {:ttl => ttl, :raw_data_ttl => raw_data_ttl, :interval => interval, :reduce_delay => reduce_delay} }
  let(:sensor){ described_class.new(name, good_init_values) }
  let(:redis){ PulseMeter.redis }

  it_should_behave_like "timeline sensor"

  describe '#new' do
    INIT_VALUE_NAMES = {
      :with_defaults => [:raw_data_ttl, :reduce_delay],
      :without_defaults => [:ttl, :interval]
    }

    it "should initialize #ttl #raw_data_ttl #interval and #name attributes" do
      sensor.name.should == name.to_s

      sensor.ttl.should == ttl
      sensor.raw_data_ttl.should == raw_data_ttl
      sensor.interval.should == interval
    end

    INIT_VALUE_NAMES[:with_defaults].each do |value|
      it "should not raise exception if #{value.inspect} is not defined" do
        values = good_init_values
        values.delete(value)
        expect {described_class.new(name, good_init_values)}.not_to raise_exception(ArgumentError)
      end

      it "should assign default value to #{value.inspect} if it is not defined" do
        values = good_init_values
        values.delete(value)
        obj = described_class.new(name, good_init_values)
        obj.send(value).should be_kind_of(Fixnum)
      end
    end

  end
end
