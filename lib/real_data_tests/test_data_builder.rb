module RealDataTests
  class TestDataBuilder
    def initialize(record, name: nil)
      @record = record
      @name = name || "#{record.class.name.underscore}_#{record.id}"
    end

    def create_dump_file
      records = RealDataTests::RecordCollector.new(@record).collect

      # Only anonymize if rules are configured in the current preset
      if RealDataTests.configuration.current_preset.anonymization_rules.any?
        puts "\nAnonymizing records..."
        anonymizer = RealDataTests::DataAnonymizer.new(RealDataTests.configuration.current_preset)
        records = anonymizer.anonymize_records(records)
      end

      dump_content = RealDataTests::PgDumpGenerator.new(records).generate
      dump_path = dump_file_path
      FileUtils.mkdir_p(File.dirname(dump_path))
      File.write(dump_path, dump_content)
      puts "\nDump file created at: #{dump_path}"
      dump_path
    end

    private

    def dump_file_path
      File.join(RealDataTests.configuration.dump_path, "#{@name}.sql")
    end
  end
end