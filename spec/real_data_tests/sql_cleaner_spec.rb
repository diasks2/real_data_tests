# spec/lib/real_data_tests/sql_cleaner_spec.rb
require 'spec_helper'

RSpec.describe RealDataTests::RSpecHelper do
  describe '#clean_sql_statement' do
    let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }
    let(:complex_settings) do
      '{"billing":{"claim_submission":"","automatic_59_modifier":"1"},' \
      '"print_settings":{"hide_logo_in_header":"0"},' \
      '"preferred_payment_types":["private-commercial-insurance","credit-card"]}'
    end
    let(:organization_sql) do
      <<~SQL
        INSERT INTO organizations
        (id, dba_name, legal_name, slug, about, plain_text_about,
        organization_type_id, organization_size_id, profile_public, test_account,
        settings, approved, deleted, submitted_for_approval, url, created_at,
        updated_at, stripe_id, domain, demo_mode, time_zone,
        insurance_billing_filterable)
        VALUES (e50d8052-4481-4246-9502-7f8e5659abcb, Ratke Group, Terry-Carroll,
        r1coul335sza439x, NULL, '', 7c4ab8dc-66ef-4617-a7c7-8a0bd49ae909,
        761e96fa-ebf8-40b3-842b-8c47901519e0, false, false, #{complex_settings},
        false, false, false, http://shields.test/dewitt_gottlieb,
        2023-10-04 16:33:02 UTC, 2024-12-09 17:28:00 UTC, '',
        rlexxgvf3pvercxg.com, false, Eastern Time (US & Canada), true)
        ON CONFLICT (id) DO NOTHING;
      SQL
    end

    def remove_whitespace(sql)
      sql.gsub(/\s+/, ' ').strip
    end

    it 'properly quotes and formats a complex organization insert statement' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(remove_whitespace(cleaned)).to include(
        "'e50d8052-4481-4246-9502-7f8e5659abcb', " \
        "'Ratke Group', " \
        "'Terry-Carroll', " \
        "'r1coul335sza439x', " \
        "NULL, " \
        "''")
    end

    it 'preserves JSON structure in settings column' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(cleaned).to include(complex_settings)
    end

    it 'handles UUIDs correctly' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(cleaned).to include("'7c4ab8dc-66ef-4617-a7c7-8a0bd49ae909'")
      expect(cleaned).to include("'761e96fa-ebf8-40b3-842b-8c47901519e0'")
    end

    it 'preserves boolean values without quotes' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(remove_whitespace(cleaned)).to include('false, false, false')
    end

    it 'properly quotes time zone string' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(cleaned).to include("'Eastern Time (US & Canada)'")
    end

    it 'properly quotes URLs' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(cleaned).to include("'http://shields.test/dewitt_gottlieb'")
    end

    it 'properly quotes domains' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(cleaned).to include("'rlexxgvf3pvercxg.com'")
    end

    it 'preserves ON CONFLICT clause with proper formatting' do
      cleaned = helper.send(:clean_sql_statement, organization_sql)
      expect(remove_whitespace(cleaned)).to match(/\) ON CONFLICT \(id\) DO NOTHING;$/)
    end
  end

  describe '#split_values' do
    let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }

    it 'correctly splits values with spaces' do
      values = "value1, 'Ratke Group', value3)"
      result = helper.send(:split_values, values)
      expect(result).to eq(['value1', "'Ratke Group'", 'value3'])
    end

    it 'handles nested JSON objects' do
      values = "value1, '{\"key\": \"value, with comma\"}', value3)"
      result = helper.send(:split_values, values)
      expect(result).to eq(['value1', "'{\"key\": \"value, with comma\"}'", 'value3'])
    end

    it 'preserves quoted strings with commas' do
      values = "'value1', 'string, with comma', 'value3')"
      result = helper.send(:split_values, values)
      expect(result).to eq(["'value1'", "'string, with comma'", "'value3'"])
    end
  end
end