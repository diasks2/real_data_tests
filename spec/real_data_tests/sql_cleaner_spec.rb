# spec/lib/real_data_tests/sql_cleaner_spec.rb
require 'spec_helper'

RSpec.describe RealDataTests::RSpecHelper do
  let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }
  let(:complex_settings) do
    '{"billing":{"claim_submission":"","automatic_59_modifier":"1"},' \
    '"print_settings":{"hide_logo_in_header":"0"},' \
    '"preferred_payment_types":["private-commercial-insurance","credit-card"]}'
  end

  def remove_whitespace(sql)
    sql.gsub(/\s+/, ' ').strip
  end

  describe '#clean_sql_statement' do
    it 'handles boolean values correctly at the end of VALUES clause' do
      sql = <<~SQL
        INSERT INTO organizations (id, name, enabled)
        VALUES ('123', 'Test Org', true)
        ON CONFLICT (id) DO NOTHING;
      SQL
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to include("VALUES ('123', 'Test Org', true)")
      expect(remove_whitespace(cleaned)).to match(/true\) ON CONFLICT/)
    end

    it 'preserves boolean false values without quotes' do
      sql = "INSERT INTO table (active) VALUES (false);"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to include("VALUES (false)")
    end

    it 'handles complex JSON settings' do
      sql = "INSERT INTO settings (id, config) VALUES (1, '#{complex_settings}');"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include(complex_settings)
    end

    it 'properly quotes UUIDs' do
      sql = "INSERT INTO table (id) VALUES (123e4567-e89b-12d3-a456-426614174000);"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include("'123e4567-e89b-12d3-a456-426614174000'")
    end

    it 'preserves NULL values without quotes' do
      sql = "INSERT INTO table (id, name) VALUES (1, NULL);"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include("NULL")
    end

    it 'preserves numeric values without quotes' do
      sql = "INSERT INTO table (id, count) VALUES (1, 42);"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include("42")
    end

    it 'handles ON CONFLICT clause correctly' do
      sql = "INSERT INTO table (id) VALUES (1) ON CONFLICT (id) DO NOTHING;"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to match(/\) ON CONFLICT \(id\) DO NOTHING;$/)
    end
  end

  describe '#clean_sql_statement' do
    it 'handles complex INSERT with multiple closing parentheses and ON CONFLICT' do
      sql = <<~SQL
        INSERT INTO users (email, active, timezone, verified)
        VALUES ('test@example.com', false, 'Eastern Time (US & Canada)', true)
        ON CONFLICT (email) DO NOTHING;
      SQL
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to include("'Eastern Time (US & Canada)'")
      expect(remove_whitespace(cleaned)).to match(/true\)\s+ON CONFLICT/)
    end

    it 'preserves spacing around ON CONFLICT clause' do
      sql = "INSERT INTO users (id) VALUES (1) ON CONFLICT (id) DO NOTHING;"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to match(/\)\s+ON CONFLICT/)
    end
  end

  describe '#clean_values' do
    let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }

    it 'correctly handles values with spaces' do
      values = "value1, 'Ratke Group', value3"
      result = helper.send(:clean_values, values)
      expect(result).to eq("'value1', 'Ratke Group', 'value3'")
    end

    it 'preserves quoted strings with commas' do
      values = "value1, 'string, with comma', value3"
      result = helper.send(:clean_values, values)
      expect(result).to eq("'value1', 'string, with comma', 'value3'")
    end

    it 'handles nested JSON objects' do
      values = "value1, '{\"key\": \"value, with comma\"}', value3"
      result = helper.send(:clean_values, values)
      expect(result).to eq("'value1', '{\"key\": \"value, with comma\"}', 'value3'")
    end

    it 'preserves boolean values without quotes' do
      values = "true, false, 'string'"
      result = helper.send(:clean_values, values)
      expect(result).to eq("true, false, 'string'")
    end
  end
end