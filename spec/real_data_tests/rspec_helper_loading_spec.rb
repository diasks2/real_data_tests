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

  describe '#load_real_test_data' do
    include_examples 'a transactional loader', :load_real_test_data
  end
end
