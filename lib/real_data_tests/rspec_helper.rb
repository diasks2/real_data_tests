module RealDataTests
  module RSpecHelper
    # Loads a SQL dump using the given strategy (default: transactional
    # loading on the ActiveRecord connection). Pass a different strategy to
    # change how the dump is executed, e.g.:
    #
    #   load_real_test_data("dump", strategy: RealDataTests::LoadStrategies::Psql)
    def load_real_test_data(name, strategy: LoadStrategies::Native)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      strategy.call(dump_path)
    end

    def load_real_test_data_native(name)
      load_real_test_data(name, strategy: LoadStrategies::Native)
    end
  end
end
