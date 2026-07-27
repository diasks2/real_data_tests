module RealDataTests
  module RSpecHelper
    # Loads a SQL dump using the given strategy (default: psql shell-out,
    # matching pre-0.5 behavior — data commits outside the caller's
    # transaction). Pass a different strategy to change how the dump is
    # executed, e.g. transactional loading on the ActiveRecord connection:
    #
    #   load_real_test_data("dump", strategy: RealDataTests::LoadStrategies::Native)
    def load_real_test_data(name, strategy: LoadStrategies::Psql)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      strategy.call(dump_path)
    end

    def load_real_test_data_native(name)
      load_real_test_data(name, strategy: LoadStrategies::Native)
    end
  end
end
