# spec/real_data_tests/record_collector_polymorphic_spec.rb

require 'spec_helper'
require 'active_record'

RSpec.describe RealDataTests::RecordCollector do
  # Set up test models
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :payments do |t|
        t.references :billable, polymorphic: true
        t.decimal :amount
        t.timestamps
      end

      create_table :insurance_companies do |t|
        t.string :name
        t.timestamps
      end

      create_table :patients do |t|
        t.string :name
        t.timestamps
      end

      create_table :facilities do |t|
        t.string :name
        t.timestamps
      end

      create_table :comments do |t|
        t.references :commentable, polymorphic: true
        t.text :content
        t.timestamps
      end
    end

    class Payment < ActiveRecord::Base
      belongs_to :billable, polymorphic: true
    end

    class InsuranceCompany < ActiveRecord::Base
      has_many :payments, as: :billable
      has_many :comments, as: :commentable
    end

    class Patient < ActiveRecord::Base
      has_many :payments, as: :billable
      has_one :comment, as: :commentable
    end

    class Facility < ActiveRecord::Base
      has_many :payments, as: :billable
      has_many :comments, as: :commentable
    end

    class Comment < ActiveRecord::Base
      belongs_to :commentable, polymorphic: true
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:payments)
    ActiveRecord::Base.connection.drop_table(:insurance_companies)
    ActiveRecord::Base.connection.drop_table(:patients)
    ActiveRecord::Base.connection.drop_table(:facilities)
    ActiveRecord::Base.connection.drop_table(:comments)
  end

  let(:insurance_company) { InsuranceCompany.create!(name: "Test Insurance") }
  let(:patient) { Patient.create!(name: "John Doe") }
  let(:facility) { Facility.create!(name: "Test Facility") }

  # Set up base configuration before each test
  before(:each) do
    RealDataTests.configure do |config|
      config.preset :test_preset do |p|
        p.include_associations_for 'Payment', :billable
        p.include_associations_for 'InsuranceCompany', :payments, :comments
        p.include_associations_for 'Patient', :payments, :comment
        p.include_associations_for 'Facility', :payments, :comments
        p.include_associations_for 'Comment', :commentable
      end
      config.use_preset(:test_preset)
    end
  end

  describe "polymorphic belongs_to associations" do
    it "collects records from polymorphic belongs_to relationships" do
      payment = Payment.create!(billable: insurance_company, amount: 100)
      collector = described_class.new(payment)
      collected_records = collector.collect

      expect(collected_records).to include(payment)
      expect(collected_records).to include(insurance_company)
    end

    it "tracks polymorphic types in collection stats" do
      # Let's add some debug output
      puts "\nCurrent preset: #{RealDataTests.configuration.current_preset}"

      # Create our test data
      insurance_company = InsuranceCompany.create!(name: "Test Insurance")
      payment1 = Payment.create!(billable: insurance_company, amount: 100)

      # Let's verify the payment data
      puts "\nPayment1 data:"
      puts "  billable_type: #{payment1.billable_type}"
      puts "  billable_id: #{payment1.billable_id}"

      # Create and run collector
      collector = described_class.new(payment1)
      collected_records = collector.collect

      # Get stats and inspect them
      stats = collector.collection_stats
      puts "\nFull collection stats:"
      puts JSON.pretty_generate(stats.transform_values(&:to_h))

      # Check the specific value we're looking for
      polymorphic_types = stats['Payment'][:polymorphic_types][:billable]
      puts "\nPolymorphic types for Payment.billable:"
      puts "  #{polymorphic_types.inspect}"

      # Run our expectation
      puts "Stats at assertion point: #{stats['Payment'][:polymorphic_types]}"

      expect(polymorphic_types).to include('InsuranceCompany')
    end
  end

  describe "polymorphic has_many associations" do
    it "collects records from polymorphic has_many relationships" do
      payment1 = Payment.create!(billable: insurance_company, amount: 100)
      payment2 = Payment.create!(billable: insurance_company, amount: 200)

      collector = described_class.new(insurance_company)
      collected_records = collector.collect

      expect(collected_records).to include(insurance_company)
      expect(collected_records).to include(payment1)
      expect(collected_records).to include(payment2)
    end

    it "respects configured limits for polymorphic has_many associations" do
      5.times { Payment.create!(billable: insurance_company, amount: 100) }

      RealDataTests.configure do |config|
        config.preset :limit_test_preset do |p|
          # Include all the base associations
          p.include_associations_for 'Payment', :billable
          p.include_associations_for 'InsuranceCompany', :payments, :comments
          p.include_associations_for 'Patient', :payments, :comment
          p.include_associations_for 'Facility', :payments, :comments
          p.include_associations_for 'Comment', :commentable

          # Add the limit configuration
          p.set_association_limit 'InsuranceCompany', :payments, 2
        end
        config.use_preset(:limit_test_preset)
      end

      collector = described_class.new(insurance_company)
      collected_records = collector.collect

      payment_count = collected_records.count { |r| r.is_a?(Payment) }
      expect(payment_count).to eq(2)
    end
  end

  describe "polymorphic has_one associations" do
    it "collects records from polymorphic has_one relationships" do
      comment = Comment.create!(commentable: patient, content: "Test comment")

      collector = described_class.new(patient)
      collected_records = collector.collect

      expect(collected_records).to include(patient)
      expect(collected_records).to include(comment)
    end
  end

  describe "nested polymorphic associations" do
    it "handles nested polymorphic relationships" do
      payment = Payment.create!(billable: insurance_company, amount: 100)
      comment = Comment.create!(commentable: insurance_company, content: "Test comment")

      collector = described_class.new(payment)
      collected_records = collector.collect

      expect(collected_records).to include(payment)
      expect(collected_records).to include(insurance_company)
      expect(collected_records).to include(comment)
    end
  end

  describe "error handling" do
    it "gracefully handles errors in polymorphic association loading" do
      payment = Payment.create!(billable: insurance_company, amount: 100)
      allow(payment).to receive(:billable).and_raise(ActiveRecord::RecordNotFound)

      collector = described_class.new(payment)
      expect { collector.collect }.not_to raise_error
    end
  end

  describe "collection statistics" do
    it "provides detailed statistics for polymorphic associations" do
      payment1 = Payment.create!(billable: insurance_company, amount: 100)
      payment2 = Payment.create!(billable: patient, amount: 200)
      comment = Comment.create!(commentable: insurance_company, content: "Test")

      collector = described_class.new(payment1)
      collector.collect

      stats = collector.instance_variable_get(:@collection_stats)
      expect(stats['Payment'][:polymorphic_types][:billable]).to include('InsuranceCompany')
      expect(stats['InsuranceCompany'][:associations]['comments']).to eq(1)
    end
  end
end