module RealDataTests
  class TestDataBuilder
    def initialize(record, name: nil)
      @record = record
      @name = name || "#{record.class.name.underscore}_#{record.id}"
    end

    def create_dump_file
      records = RealDataTests::RecordCollector.new(@record).collect

      # Only anonymize if rules are configured
      if RealDataTests.configuration.anonymization_rules.any?
        puts "\nAnonymizing records..."
        RealDataTests::DataAnonymizer.new(records).anonymize_records
      end

      dump_content = RealDataTests::PgDumpGenerator.new(records).generate

      dump_path = dump_file_path
      FileUtils.mkdir_p(File.dirname(dump_path))

      # Write the SQL content to file
      File.write(dump_path, dump_content)

      dump_path
    end

    private

    def dump_file_path
      File.join(RealDataTests.configuration.dump_path, "#{@name}.sql")
    end
  end
end