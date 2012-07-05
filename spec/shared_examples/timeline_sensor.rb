shared_examples_for "timeline sensor" do |extra_init_values, default_event|
  class Dummy
    include PulseMeter::Mixins::Dumper
    def name; :dummy end
    def redis; PulseMeter.redis; end
  end

  let(:name){ :some_value_with_history }
  let(:ttl){ 100 }
  let(:raw_data_ttl){ 30 }
  let(:interval){ 5 }
  let(:reduce_delay){ 3 }
  let(:good_init_values){ {:ttl => ttl, :raw_data_ttl => raw_data_ttl, :interval => interval, :reduce_delay => reduce_delay}.merge(extra_init_values || {}) }
  let!(:sensor){ described_class.new(name, good_init_values) }
  let(:dummy) {Dummy.new}
  let(:base_class){ PulseMeter::Sensor::Base }
  let(:redis){ PulseMeter.redis }
  let(:sample_event) {default_event || 123}

  before(:each) do
    @interval_id = (Time.now.to_i / interval) * interval
    @raw_data_key = sensor.raw_data_key(@interval_id)
    @next_raw_data_key = sensor.raw_data_key(@interval_id + interval)
    @start_of_interval = Time.at(@interval_id)
  end

  describe "#dump" do
    it "should be dumped succesfully" do
      expect {sensor.dump!}.not_to raise_exception
    end
  end

  describe ".restore" do
    before do
      # no need to call sensor.dump! explicitly for it
      # will be called automatically after creation
      @restored = base_class.restore(sensor.name)
    end

    it "should restore #{described_class} instance" do
      @restored.should be_instance_of(described_class)
    end

    it "should restore object with the same data" do
      def inner_data(obj)
        obj.instance_variables.sort.map {|v| obj.instance_variable_get(v)}
      end

      inner_data(sensor).should == inner_data(@restored)
    end
  end

  describe "#event" do
    it "should write events to redis" do
      expect{
          sensor.event(sample_event)
      }.to change{ redis.keys('*').count }.by(1)
    end

    it "should write data so that it totally expires after :raw_data_ttl" do
      key_count = redis.keys('*').count
      sensor.event(sample_event)
      Timecop.freeze(Time.now + raw_data_ttl + 1) do
        redis.keys('*').count.should == key_count
      end
    end

    it "should write data to bucket indicated by truncated timestamp" do
      key = sensor.raw_data_key(@interval_id)
      expect{
        Timecop.freeze(@start_of_interval) do
          sensor.event(sample_event)
        end
      }.to change{ redis.ttl(key) }
    end

    it "returns true if event processed correctly" do
      sensor.event(sample_event).should be_true
    end

    it "catches StandardErrors and returns false" do
      sensor.stub(:aggregate_event) {raise StandardError}
      sensor.event(sample_event).should be_false
    end
  end

  describe "#summarize" do
    it "should convert data stored by raw_data_key to a value defined only by stored data" do
      Timecop.freeze(@start_of_interval) do
        sensor.event(sample_event)
      end
      Timecop.freeze(@start_of_interval + interval) do
        sensor.event(sample_event)
      end
      sensor.summarize(@raw_data_key).should == sensor.summarize(@next_raw_data_key)
      sensor.summarize(@raw_data_key).should_not be_nil
    end
  end

  describe "#reduce" do
    it "should store summarized value into data_key" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      val = sensor.summarize(@raw_data_key)
      val.should_not be_nil
      sensor.reduce(@interval_id)
      redis.get(sensor.data_key(@interval_id)).should == val.to_s
    end

    it "should remove original raw_data_key" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      expect{
        sensor.reduce(@interval_id)
      }.to change{ redis.keys(sensor.raw_data_key(@interval_id)).count }.from(1).to(0)
    end

    it "should expire stored summarized data" do
      Timecop.freeze(@start_of_interval) do
        sensor.event(sample_event)
        sensor.reduce(@interval_id)
        redis.keys(sensor.data_key(@interval_id)).count.should == 1
      end
      Timecop.freeze(@start_of_interval + ttl + 1) do
        redis.keys(sensor.data_key(@interval_id)).count.should == 0
      end
    end

    it "should not store data if there is no corresponding raw data" do
      Timecop.freeze(@start_of_interval) do
        sensor.reduce(@interval_id)
        redis.keys(sensor.data_key(@interval_id)).count.should == 0
      end
    end
  end

  describe "#reduce_all_raw" do
    it "should reduce all data older than reduce_delay" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      val0 = sensor.summarize(@raw_data_key)
      Timecop.freeze(@start_of_interval + interval){ sensor.event(sample_event) }
      val1 = sensor.summarize(@next_raw_data_key)
      expect{
        Timecop.freeze(@start_of_interval + interval + interval + reduce_delay + 1) { sensor.reduce_all_raw }
      }.to change{ redis.keys(sensor.raw_data_key('*')).count }.from(2).to(0)

      redis.get(sensor.data_key(@interval_id)).should == val0.to_s
      redis.get(sensor.data_key(@interval_id + interval)).should == val1.to_s
    end

    it "should not reduce fresh data" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }

      expect{
        Timecop.freeze(@start_of_interval + interval + reduce_delay - 1) { sensor.reduce_all_raw }
      }.not_to change{ redis.keys(sensor.raw_data_key('*')).count }

      expect{
        Timecop.freeze(@start_of_interval + interval + reduce_delay - 1) { sensor.reduce_all_raw }
      }.not_to change{ redis.keys(sensor.data_key('*')).count }
    end
  end

  describe ".reduce_all_raw" do
    it "should silently skip objects without reduce logic" do
      dummy.dump!
      expect {described_class.reduce_all_raw}.not_to raise_exception
    end

    it "should send reduce_all_raw to all dumped objects" do
      described_class.any_instance.should_receive(:reduce_all_raw)
      described_class.reduce_all_raw
    end
  end

  describe "#timeline_within" do
    it "shoulde raise exception unless both arguments are Time objects" do
      [:q, nil, -1].each do |bad_value|
        expect{ sensor.timeline_within(Time.now, bad_value) }.to raise_exception(ArgumentError)
        expect{ sensor.timeline_within(bad_value, Time.now) }.to raise_exception(ArgumentError)
      end
    end

    it "should return an array of SensorData objects corresponding to stored data for passed interval" do
      sensor.event(sample_event)
      now = Time.now
      timeline = sensor.timeline_within(now - 1, now)
      timeline.should be_kind_of(Array)
      timeline.each{|i| i.should be_kind_of(SensorData) }
    end

    it "should return array of results containing as many results as there are sensor interval beginnings in the passed interval" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      Timecop.freeze(@start_of_interval + interval){ sensor.event(sample_event) }

      future = @start_of_interval + 3600
      Timecop.freeze(future) do
        sensor.timeline_within(
          Time.at(@start_of_interval + interval - 1),
          Time.at(@start_of_interval + interval + 1)
        ).size.should == 1

        sensor.timeline_within(
          Time.at(@start_of_interval - 1),
          Time.at(@start_of_interval + interval + 1)
        ).size.should == 2
      end

      Timecop.freeze(@start_of_interval + interval + 2) do
        sensor.timeline_within(
          Time.at(@start_of_interval + interval + 1),
          Time.at(@start_of_interval + interval + 2)
        ).size.should == 0
      end
    end
  end

  describe "#timeline" do

    it "should request timeline within interval from given number of seconds ago till now" do
      Timecop.freeze do
        now = Time.now
        ago = interval * 100
        sensor.timeline(ago).should == sensor.timeline_within(now - ago, now)
      end
    end

    it "should return array of results containing as many results as there are sensor interval beginnings in the passed interval" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      Timecop.freeze(@start_of_interval + interval){ sensor.event(sample_event) }

      Timecop.freeze(@start_of_interval + interval + 1) do
        sensor.timeline(2).size.should == 1
      end
      Timecop.freeze(@start_of_interval + interval + 2) do
        sensor.timeline(1).size.should == 0
      end
      Timecop.freeze(@start_of_interval + interval + 1) do
        sensor.timeline(2 + interval).size.should == 2
      end
    end
  end

  describe "SensorData value for an interval" do
    def check_sensor_data(sensor, value)
      data = sensor.timeline(2).first
      data.value.should == value
      data.start_time.to_i.should == @interval_id
    end

    it "should contain summarized value stored by data_key for reduced intervals" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      sensor.reduce(@interval_id)
      Timecop.freeze(@start_of_interval + 1){
        check_sensor_data(sensor, redis.get(sensor.data_key(@interval_id)))
      }
    end

    it "should contain summarized value based on raw data for intervals not yet reduced" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      Timecop.freeze(@start_of_interval + 1){
        check_sensor_data(sensor, sensor.summarize(@raw_data_key))
      }
    end

    it "should contain nil for intervals without any data" do
      Timecop.freeze(@start_of_interval + 1) {
        check_sensor_data(sensor, nil)
      }
    end
  end

  describe "#cleanup" do
    it "should remove all sensor data (raw data, reduced data, annotations) from redis" do
      Timecop.freeze(@start_of_interval){ sensor.event(sample_event) }
      sensor.reduce(@interval_id)
      Timecop.freeze(@start_of_interval + interval){ sensor.event(sample_event) }
      sensor.annotate("Fooo sensor")

      sensor.cleanup
      redis.keys('*').should be_empty
    end
  end

end
