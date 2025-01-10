module RealDataTests
  class TestDataBuilder
    def initialize(record, name: nil)
      @record = record
      @name = name || "#{record.class.name.underscore}_#{record.id}"
    end

    def create_dump_file
      records = RecordCollector.new(@record).collect
      dump_commands = PgDumpGenerator.new(records).generate

      dump_path = dump_file_path
      FileUtils.mkdir_p(File.dirname(dump_path))

      # Execute pg_dump and save the output directly to file
      command = "#{dump_commands} > #{dump_path}"
      unless system(command)
        raise Error, "Failed to create dump file: #{command}"
      end

      dump_path
    end

    private

    def dump_file_path
      File.join(RealDataTests.configuration.dump_path, "#{@name}.sql")
    end
  end
end