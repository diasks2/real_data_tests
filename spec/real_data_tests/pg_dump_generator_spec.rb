# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RealDataTests::PgDumpGenerator do
  describe '#generate' do
    context 'with JSONB fields' do
      before(:all) do
        # Define our mock class at the top level
        class MockTreatmentReport
          attr_reader :id, :service_history_log_data

          def initialize(id, service_history_log_data)
            @id = id
            @service_history_log_data = service_history_log_data
          end

          def self.table_name
            'treatment_reports'
          end

          def self.column_names
            ['id', 'service_history_log_data']
          end

          def self.columns_hash
            {
              'id' => OpenStruct.new(
                name: 'id',
                type: :integer,
                sql_type: 'integer',
                array: false
              ),
              'service_history_log_data' => OpenStruct.new(
                name: 'service_history_log_data',
                type: :jsonb,
                sql_type: 'jsonb',
                array: false
              )
            }
          end

          def self.reflect_on_all_associations(macro = nil)
            []
          end

          def [](name)
            instance_variable_get("@#{name}")
          end
        end
      end

      after(:all) do
        Object.send(:remove_const, :MockTreatmentReport) if defined?(MockTreatmentReport)
      end

      let(:record_with_empty_jsonb) do
        MockTreatmentReport.new(1, "")
      end

      let(:record_with_nil_jsonb) do
        MockTreatmentReport.new(1, nil)
      end

      let(:record_with_json_data) do
        MockTreatmentReport.new(1, { "key" => "value" })
      end

      it 'converts empty string JSONB to empty object {}' do
        generator = described_class.new([record_with_empty_jsonb])
        sql = generator.generate

        expect(sql).to include("'{}'")
        expect(sql).not_to include("'\"\"'")
      end

      it 'converts nil JSONB to NULL' do
        generator = described_class.new([record_with_nil_jsonb])
        sql = generator.generate

        expect(sql).to include("NULL")
      end

      it 'properly handles valid JSON data' do
        generator = described_class.new([record_with_json_data])
        sql = generator.generate

        expect(sql).to include('\'{"key":"value"}\'')
      end

      it 'generates valid INSERT statements' do
        generator = described_class.new([record_with_empty_jsonb])
        sql = generator.generate

        # More specific expectations for the SQL statement
        expect(sql).to include("INSERT INTO treatment_reports")
        expect(sql).to include("(id, service_history_log_data)")
        expect(sql).to include("VALUES (1, '{}')")
        expect(sql).to include("ON CONFLICT (id) DO NOTHING")
      end
    end
  end
end