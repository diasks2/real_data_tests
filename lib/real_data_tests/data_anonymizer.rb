module RealDataTests
  class DataAnonymizer
    def initialize(records)
      @records = records
      @anonymization_rules = RealDataTests.configuration.anonymization_rules
    end

    def anonymize_records
      @records.each do |record|
        anonymize_record(record) if should_anonymize?(record)
      end
    end

    private

    def should_anonymize?(record)
      @anonymization_rules.key?(record.class.name)
    end

    def anonymize_record(record)
      rules = @anonymization_rules[record.class.name]

      rules.each do |attribute, faker_method|
        begin
          # Parse the faker method string (e.g., "Faker::Name.first_name")
          faker_class, faker_method = faker_method.split('::')[1..].join('::').split('.')

          # Get the Faker class dynamically
          faker_class = Object.const_get("Faker::#{faker_class}")

          # Set the anonymized value
          record.send("#{attribute}=", faker_class.send(faker_method))
          record.save!
        rescue => e
          raise Error, "Failed to anonymize #{attribute} using #{faker_method}: #{e.message}"
        end
      end
    end
  end
end