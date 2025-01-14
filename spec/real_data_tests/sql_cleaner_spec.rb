# spec/lib/real_data_tests/sql_cleaner_spec.rb
require 'spec_helper'

RSpec.describe RealDataTests::RSpecHelper do
  let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }
  let(:complex_json_settings) do
    '{"billing":{"claim_submission":"","automatic_59_modifier":"1"},' \
    '"print_settings":{"hide_logo_in_header":"0"},' \
    '"patient_portal_settings":{"patient_invoices":"none"},' \
    '"preferred_payment_types":["private-commercial-insurance","credit-card"]}'
  end

  def remove_whitespace(sql)
    sql.gsub(/\s+/, ' ').strip
  end

  describe '#clean_sql_statement' do
    it 'handles complex INSERT with JSON and ON CONFLICT' do
      sql = <<~SQL
        INSERT INTO organizations (id, name, settings, active, timezone, verified)
        VALUES ('e50d8052-4481-4246-9502-7f8e5659abcb', 'Test Org', '#{complex_json_settings}', false, 'Eastern Time (US & Canada)', true)
        ON CONFLICT (id) DO NOTHING;
      SQL

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to include("'e50d8052-4481-4246-9502-7f8e5659abcb'")
      expect(remove_whitespace(cleaned)).to include("'Test Org'")
      expect(remove_whitespace(cleaned)).to include(complex_json_settings)
      expect(remove_whitespace(cleaned)).to include("'Eastern Time (US & Canada)'")
      expect(remove_whitespace(cleaned)).to match(/true\)\s+ON CONFLICT/)
      expect(remove_whitespace(cleaned)).to match(/DO NOTHING;$/)  # Changed this line
    end

    it 'preserves nested JSON with commas and quotes' do
      json_with_commas = '{"values":["first,value", "second,value"]}'
      sql = <<~SQL
        INSERT INTO config (id, data)
        VALUES (1, '#{json_with_commas}')
        ON CONFLICT (id) DO NOTHING;
      SQL

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include(json_with_commas)
    end

    it 'handles multiple complex values with various types' do
      sql = <<~SQL
        INSERT INTO organizations
        (id, name, active, config, created_at, count, uuid)
        VALUES
        ('1', 'Company, Inc.', true, '{"key": "value"}', '2025-01-14 10:00:00', 42, 'abc-123')
        ON CONFLICT (id) DO NOTHING;
      SQL

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include("'Company, Inc.'")
      expect(cleaned).to include("true")
      expect(cleaned).to include("'2025-01-14 10:00:00'")
      expect(cleaned).to include("42")
      expect(cleaned).to include("'abc-123'")
    end

    it 'handles NULL values correctly in complex statements' do
      sql = <<~SQL
        INSERT INTO organizations
        (id, name, parent_id, config)
        VALUES
        ('1', 'Test Corp', NULL, '{"setting": null}')
        ON CONFLICT (id) DO NOTHING;
      SQL

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include("NULL")
      expect(cleaned).to include("'Test Corp'")
      expect(cleaned).to include('{"setting": null}')
    end

    it 'preserves spacing in complex JSON strings' do
      json_with_spaces = '{"description": "This is a test with spaces and, commas"}'
      sql = "INSERT INTO data (id, config) VALUES (1, '#{json_with_spaces}');"

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include(json_with_spaces)
    end

    it 'handles actual production SQL with complex settings' do
      sql = <<~SQL
        VALUES ('e50d8052-4481-4246-9502-7f8e5659abcb', 'Hettinger, Stiedemann and White',
        'Wuckert-Bartoletti', 'fd7pfbe3je79fpp0', NULL, '',
        '7c4ab8dc-66ef-4617-a7c7-8a0bd49ae909', '761e96fa-ebf8-40b3-842b-8c47901519e0',
        false, false,
        '{"billing":{"claim_submission":"","automatic_59_modifier":"1"},"print_settings":{"hide_logo_in_header":"0"},"preferred_payment_types":["private-commercial-insurance","credit-card"]}',
        false, false, false, 'http://leannon.test/burl_pfeffer',
        '2023-10-04 16:33:02 UTC', '2024-12-09 17:28:00 UTC', '',
        'ebumlenoinivyghb.com', false, 'Eastern Time (US & Canada)', true)
        ON CONFLICT (id) DO NOTHING;
      SQL

      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to include("'Hettinger, Stiedemann and White'")
      expect(remove_whitespace(cleaned)).to include("'Eastern Time (US & Canada)'")
      expect(remove_whitespace(cleaned)).to match(/true\)\s+ON CONFLICT/)
      expect(remove_whitespace(cleaned)).to match(/DO NOTHING;$/)  # Changed this line
    end

    it 'handles VALUES statement without INSERT INTO' do
      sql = "VALUES (e50d8052-4481-4246-9502-7f8e5659abcb, Lebsack, Glover, false);"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to eq(
        "VALUES ('e50d8052-4481-4246-9502-7f8e5659abcb', 'Lebsack', 'Glover', false);"
      )
    end

    it 'properly quotes UUIDs in bare VALUES statements' do
      sql = "VALUES (e50d8052-4481-4246-9502-7f8e5659abcb, 'Test');"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(remove_whitespace(cleaned)).to eq(
        "VALUES ('e50d8052-4481-4246-9502-7f8e5659abcb', 'Test');"
      )
    end
  end

  describe '#clean_complex_values' do
    it 'handles values with nested JSON correctly' do
      values = "'id123', 'name', '{\"key\": \"value\"}', true"
      result = helper.send(:clean_complex_values, values)
      expect(result).to eq("'id123', 'name', '{\"key\": \"value\"}', true")
    end

    it 'preserves complex JSON structures' do
      values = "'id', '#{complex_json_settings}', false"
      result = helper.send(:clean_complex_values, values)
      expect(result).to include(complex_json_settings)
      expect(result).to end_with(", false")
    end
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
      sql = "INSERT INTO settings (id, config) VALUES (1, '#{complex_json_settings}');"
      cleaned = helper.send(:clean_sql_statement, sql)
      expect(cleaned).to include(complex_json_settings)
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

  describe '#clean_complex_values' do
    let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }

    it 'correctly handles values with spaces' do
      values = "value1, 'Ratke Group', value3"
      result = helper.send(:clean_complex_values, values)
      expect(result).to eq("'value1', 'Ratke Group', 'value3'")
    end

    it 'preserves quoted strings with commas' do
      values = "value1, 'string, with comma', value3"
      result = helper.send(:clean_complex_values, values)
      expect(result).to eq("'value1', 'string, with comma', 'value3'")
    end

    it 'handles nested JSON objects' do
      values = "value1, '{\"key\": \"value, with comma\"}', value3"
      result = helper.send(:clean_complex_values, values)
      expect(result).to eq("'value1', '{\"key\": \"value, with comma\"}', 'value3'")
    end

    it 'preserves boolean values without quotes' do
      values = "true, false, 'string'"
      result = helper.send(:clean_complex_values, values)
      expect(result).to eq("true, false, 'string'")
    end
  end
end