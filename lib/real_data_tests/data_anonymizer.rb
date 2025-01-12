# lib/real_data_tests/data_anonymizer.rb
require 'faker'

module RealDataTests
  class DataAnonymizer
    def initialize(preset_config)
      @preset_config = preset_config
    end

    def anonymize_records(records)
      records.map do |record|
        anonymize_record(record)
      end
    end

    def anonymize_record(record)
      return record unless should_anonymize?(record)

      anonymization_rules = @preset_config.anonymization_rules[record.class.name]
      anonymization_rules.each do |attribute, anonymizer|
        begin
          new_value = case anonymizer
                     when String
                       process_faker_string(anonymizer)
                     when Proc, Lambda
                       anonymizer.call(record)
                     else
                       raise Error, "Unsupported anonymizer type: #{anonymizer.class}"
                     end
          record.send("#{attribute}=", new_value)
        rescue => e
          raise Error, "Failed to anonymize #{attribute} using #{anonymizer.inspect}: #{e.message}"
        end
      end
      record
    end

    private

    def should_anonymize?(record)
      @preset_config.anonymization_rules.key?(record.class.name)
    end

    def process_faker_string(faker_method)
      faker_class, faker_method = faker_method.split('::')[1..].join('::').split('.')
      faker_class = Object.const_get("Faker::#{faker_class}")
      faker_class.send(faker_method)
    rescue => e
      raise Error, "Failed to process Faker method '#{faker_method}': #{e.message}"
    end
  end
end