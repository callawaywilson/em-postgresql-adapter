require 'spec_helper'

describe EM::DB::FiberedPostgresConnection, 'plain integration into active_record' do

  before :each do
    ActiveRecord::Base.establish_connection(database_connection_config)
  end

  it "is a sane database.yml file" do
    database_connection_config['adapter'].should == 'em_postgresql'
  end

  it "uses an identifiable driver" do
    ActiveRecord::Base.connection.should be_instance_of(ActiveRecord::ConnectionAdapters::EMPostgreSQLAdapter)
  end

  it "can connect outside of eventmachine" do
    result = ActiveRecord::Base.connection.execute('SELECT 42')
    result.values.should == [['42']]
  end

end

describe EM::DB::FiberedPostgresConnection, 'integration with active_record inside an event_machine context', :type => :eventmachine do
  SLEEP_TIME = 0.2

  before(:each) do
    ActiveRecord::Base.establish_connection(database_connection_config)
  end

  it "can establish a connection and execute a query while running inside eventmachine" do
    result = nil
    em {
      Fiber.new {
        result = ActiveRecord::Base.connection.execute('SELECT 42').values
        done
      }.resume
    }
    result.should == [['42']]
  end

  it "can execute multiple queries on parallel fibers concurrently" do
    start = Time.now
    results = []
    em {
      Fiber.new {
        results << ActiveRecord::Base.connection.execute("SELECT pg_sleep(#{SLEEP_TIME}), 42").values
        done if results.length == 2
      }.resume

      Fiber.new {
        results << ActiveRecord::Base.connection.execute("SELECT pg_sleep(#{SLEEP_TIME}), 43").values
        done if results.length == 2
      }.resume
    }

    (Time.now - start).should be_within(SLEEP_TIME * 0.15).of(SLEEP_TIME)
  end


  it "can collect values from multiple queries on a single fiber" do
    results = []
    em {
      Fiber.new {
        results << ActiveRecord::Base.connection.execute("SELECT 42").values
        results << ActiveRecord::Base.connection.execute("SELECT 43").values
        done
      }.resume
    }
    results.flatten.should include('42')
    results.flatten.should include('43')
  end

  it "raises an error if not called inside a fiber" do
    em {
      expect {
        ActiveRecord::Base.connection.execute('SELECT 42')
      }.to raise_error(ActiveRecord::StatementInvalid, /FiberError/)
      done
    }
  end

end