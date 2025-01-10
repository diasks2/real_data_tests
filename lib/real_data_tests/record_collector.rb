module RealDataTests
  class RecordCollector
    def initialize(record)
      @record = record
      @collected_records = Set.new
    end

    def collect
      collect_record(@record)
      @collected_records.to_a
    end

    private

    def collect_record(record)
      return if @collected_records.include?(record)

      @collected_records.add(record)
      collect_associations(record)
    end

    def collect_associations(record)
      record.class.reflect_on_all_associations.each do |association|
        next if RealDataTests.configuration.excluded_associations.include?(association.name)

        related_records = case association.macro
        when :belongs_to, :has_one
          Array(record.send(association.name))
        when :has_many, :has_and_belongs_to_many
          record.send(association.name).to_a
        end

        related_records.each { |related_record| collect_record(related_record) }
      end
    end
  end
end