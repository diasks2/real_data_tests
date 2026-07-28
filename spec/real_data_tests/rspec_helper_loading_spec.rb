require 'spec_helper'
require 'tmpdir'

RSpec.describe RealDataTests::RSpecHelper, 'data loading' do
  let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }
  let(:connection) { ActiveRecord::Base.connection }

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @dump_dir = dir
      original_dump_path = RealDataTests.configuration.dump_path
      RealDataTests.configuration.dump_path = dir
      begin
        example.run
      ensure
        RealDataTests.configuration.dump_path = original_dump_path
      end
    end
  end

  before(:each) do
    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS rdt_test_records (
        id text PRIMARY KEY,
        name text,
        payload text
      );
    SQL
    connection.execute('DELETE FROM rdt_test_records;')
  end

  after(:each) do
    connection.execute('DROP TABLE IF EXISTS rdt_test_records;')
  end

  def write_fixture(name, content)
    File.write(File.join(@dump_dir, "#{name}.sql"), content)
  end

  def record_count
    connection.select_value('SELECT COUNT(*) FROM rdt_test_records').to_i
  end

  INSERT_DUMP = <<~SQL
    INSERT INTO rdt_test_records (id, name, payload) VALUES ('1', 'Alpha', NULL) ON CONFLICT (id) DO NOTHING;
    INSERT INTO rdt_test_records (id, name, payload) VALUES ('2', 'Beta', NULL) ON CONFLICT (id) DO NOTHING;
  SQL

  TRICKY_DUMP = <<~SQL
    SET client_min_messages = warning;
    INSERT INTO rdt_test_records (id, name, payload) VALUES ('1', 'a;b', '{"note": "semi;colon", "zone": "Eastern Time (US & Canada)"}') ON CONFLICT (id) DO NOTHING;
    INSERT INTO rdt_test_records (id, name, payload) VALUES ('2', 'it''s; fine', NULL) ON CONFLICT (id) DO NOTHING;
  SQL

  COPY_DUMP = [
    "COPY rdt_test_records (id, name, payload) FROM stdin;",
    "1\tAlpha\t\\N",
    "2\tBeta\t\\N",
    "\\.",
    ""
  ].join("\n")

  shared_examples 'a transactional loader' do |method|
    it 'loads a plain INSERT dump' do
      write_fixture('insert_dump', INSERT_DUMP)
      helper.public_send(method, 'insert_dump')
      expect(record_count).to eq(2)
    end

    it 'participates in the caller transaction (rolls back cleanly)' do
      write_fixture('insert_dump', INSERT_DUMP)
      ActiveRecord::Base.transaction do
        helper.public_send(method, 'insert_dump')
        expect(record_count).to eq(2)
        raise ActiveRecord::Rollback
      end
      expect(record_count).to eq(0)
    end

    it 'handles semicolons inside string literals and JSON' do
      write_fixture('tricky_dump', TRICKY_DUMP)
      helper.public_send(method, 'tricky_dump')
      expect(record_count).to eq(2)
      expect(connection.select_value("SELECT name FROM rdt_test_records WHERE id = '1'")).to eq('a;b')
      expect(connection.select_value("SELECT payload FROM rdt_test_records WHERE id = '1'")).to include('semi;colon')
      expect(connection.select_value("SELECT name FROM rdt_test_records WHERE id = '2'")).to eq("it's; fine")
    end

    it 'loads a COPY ... FROM stdin dump' do
      write_fixture('copy_dump', COPY_DUMP)
      helper.public_send(method, 'copy_dump')
      expect(record_count).to eq(2)
      expect(connection.select_value("SELECT name FROM rdt_test_records WHERE id = '2'")).to eq('Beta')
    end

    it 'rolls back COPY data with the caller transaction' do
      write_fixture('copy_dump', COPY_DUMP)
      ActiveRecord::Base.transaction do
        helper.public_send(method, 'copy_dump')
        expect(record_count).to eq(2)
        raise ActiveRecord::Rollback
      end
      expect(record_count).to eq(0)
    end

    it 'raises RealDataTests::Error when the file is missing' do
      expect {
        helper.public_send(method, 'nope')
      }.to raise_error(RealDataTests::Error, /Test data file not found/)
    end

    it 'restores session_replication_role after a failing dump' do
      write_fixture('bad_dump', "INSERT INTO rdt_test_records (id) VALUES ('1');\nTOTALLY NOT SQL;\n")
      expect {
        helper.public_send(method, 'bad_dump')
      }.to raise_error(ActiveRecord::StatementInvalid)
      expect(connection.select_value('SHOW session_replication_role')).to eq('origin')
    end
  end

  describe '#load_real_test_data_native' do
    include_examples 'a transactional loader', :load_real_test_data_native
  end

  describe '#load_real_test_data with the Native strategy' do
    let(:helper) do
      base = Class.new { include RealDataTests::RSpecHelper }.new
      wrapper = Object.new
      wrapper.define_singleton_method(:load) do |name|
        base.load_real_test_data(name, strategy: RealDataTests::LoadStrategies::Native)
      end
      wrapper
    end

    include_examples 'a transactional loader', :load
  end

  describe '#load_real_test_data' do
    it 'accepts a strategy via dependency injection' do
      write_fixture('insert_dump', INSERT_DUMP)
      helper.load_real_test_data('insert_dump', strategy: RealDataTests::LoadStrategies::Native)
      expect(record_count).to eq(2)
    end

    it 'passes the dump path to the injected strategy' do
      write_fixture('insert_dump', INSERT_DUMP)
      strategy = double('strategy')
      expect(strategy).to receive(:call).with(File.join(@dump_dir, 'insert_dump.sql'))
      helper.load_real_test_data('insert_dump', strategy: strategy)
    end

    it 'raises before invoking the strategy when the file is missing' do
      strategy = double('strategy')
      expect(strategy).not_to receive(:call)
      expect {
        helper.load_real_test_data('nope', strategy: strategy)
      }.to raise_error(RealDataTests::Error, /Test data file not found/)
    end
  end

  describe 'with the Psql strategy' do
    let(:database) { ENV.fetch('PGDATABASE', 'real_data_tests_test') }

    def psql(sql)
      `psql -d #{database} -t -A -q -c "#{sql}" 2>&1`.strip
    end

    before(:each) do
      psql('CREATE TABLE IF NOT EXISTS rdt_psql_records (id text PRIMARY KEY, name text);')
    end

    after(:each) do
      psql('DROP TABLE IF EXISTS rdt_psql_records;')
    end

    it 'loads the dump via psql, committing outside the caller transaction' do
      write_fixture('psql_dump', "INSERT INTO rdt_psql_records (id, name) VALUES ('1', 'Alpha');\n")
      helper.load_real_test_data('psql_dump', strategy: RealDataTests::LoadStrategies::Psql)
      expect(psql('SELECT COUNT(*) FROM rdt_psql_records')).to eq('1')
    end

    it 'is the default strategy of load_real_test_data (backwards compatible)' do
      write_fixture('psql_dump', "INSERT INTO rdt_psql_records (id, name) VALUES ('1', 'Alpha');\n")
      helper.load_real_test_data('psql_dump')
      expect(psql('SELECT COUNT(*) FROM rdt_psql_records')).to eq('1')
    end

    it 'handles dump paths containing spaces and shell metacharacters' do
      dir = File.join(@dump_dir, "with space'and quote")
      Dir.mkdir(dir)
      File.write(File.join(dir, 'space_dump.sql'), "INSERT INTO rdt_psql_records (id, name) VALUES ('1', 'Alpha');\n")
      RealDataTests.configuration.dump_path = dir

      helper.load_real_test_data('space_dump')
      expect(psql('SELECT COUNT(*) FROM rdt_psql_records')).to eq('1')
    end

    it 'supports psql meta-commands in the dump' do
      write_fixture('meta_dump', <<~SQL)
        \\set record_name Alpha
        INSERT INTO rdt_psql_records (id, name) VALUES ('1', :'record_name');
      SQL
      helper.load_real_test_data('meta_dump', strategy: RealDataTests::LoadStrategies::Psql)
      expect(psql("SELECT name FROM rdt_psql_records WHERE id = '1'")).to eq('Alpha')
    end
  end
end
