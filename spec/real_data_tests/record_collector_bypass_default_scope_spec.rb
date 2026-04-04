require "spec_helper"
require "active_record"

RSpec.describe RealDataTests::RecordCollector, "bypass_default_scope" do
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :authors, force: true do |t|
        t.string :name
        t.timestamps
      end

      create_table :articles, force: true do |t|
        t.references :author
        t.text :content
        t.string :status, default: "draft"
        t.datetime :deleted_at
        t.timestamps
      end

      create_table :taggings, force: true do |t|
        t.references :taggable, polymorphic: true
        t.string :tag_name
        t.timestamps
      end

      create_table :publishers, force: true do |t|
        t.string :name
        t.datetime :deleted_at
        t.timestamps
      end

      create_table :books, force: true do |t|
        t.references :publisher
        t.string :title
        t.timestamps
      end

      create_table :profiles, force: true do |t|
        t.references :author
        t.string :bio
        t.datetime :deleted_at
        t.timestamps
      end

      create_table :article_comments, force: true do |t|
        t.references :article
        t.text :body
        t.timestamps
      end

      create_table :profile_details, force: true do |t|
        t.references :profile
        t.string :website
        t.timestamps
      end
    end

    class Author < ActiveRecord::Base
      has_many :articles
      has_many :published_articles, -> { where(status: "published") }, class_name: "Article"
      has_many :article_comments, through: :articles
      has_one :profile
      has_one :profile_detail, through: :profile
    end

    class Profile < ActiveRecord::Base
      default_scope { where(deleted_at: nil) }

      belongs_to :author
      has_one :profile_detail
    end

    class ProfileDetail < ActiveRecord::Base
      belongs_to :profile
    end

    class Article < ActiveRecord::Base
      default_scope { where(deleted_at: nil) }

      belongs_to :author
      has_many :taggings, as: :taggable
      has_many :article_comments
    end

    class ArticleComment < ActiveRecord::Base
      belongs_to :article
    end

    class Tagging < ActiveRecord::Base
      belongs_to :taggable, polymorphic: true
    end

    class Publisher < ActiveRecord::Base
      default_scope { where(deleted_at: nil) }

      has_many :books
    end

    class Book < ActiveRecord::Base
      belongs_to :publisher
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:authors)
    ActiveRecord::Base.connection.drop_table(:articles)
    ActiveRecord::Base.connection.drop_table(:taggings)
    ActiveRecord::Base.connection.drop_table(:publishers)
    ActiveRecord::Base.connection.drop_table(:books)
    ActiveRecord::Base.connection.drop_table(:profiles)
    ActiveRecord::Base.connection.drop_table(:article_comments)
    ActiveRecord::Base.connection.drop_table(:profile_details)
  end

  describe "has_many association on a model with default_scope" do
    let(:author) { Author.create!(name: "Mike") }
    let!(:active_article) { Article.create!(author: author, content: "Active article") }
    let!(:deleted_article) do
      Article.create!(author: author, content: "Deleted article", deleted_at: Time.now)
    end

    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Author", :articles
            p.include_associations_for "Article", :author
          end
          config.use_preset(:bypass_test)
        end
      end

      it "collects soft-deleted records" do
        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(author)
        expect(collected_records).to include(active_article)
        expect(collected_records).to include(deleted_article)
      end
    end

    context "when bypass_default_scope is not enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :no_bypass_test do |p|
            p.include_associations_for "Author", :articles
            p.include_associations_for "Article", :author
          end
          config.use_preset(:no_bypass_test)
        end
      end

      it "does not collect soft-deleted records" do
        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(author)
        expect(collected_records).to include(active_article)
        expect(collected_records).not_to include(deleted_article)
      end
    end
  end

  describe "scoped has_many association on a model with default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_scoped_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Author", :published_articles
            p.include_associations_for "Article", :author
          end
          config.use_preset(:bypass_scoped_test)
        end
      end

      it "removes default_scope but preserves the association scope" do
        author = Author.create!(name: "Scoped Test")
        published_active = Article.create!(author: author, content: "Published active", status: "published")
        published_deleted = Article.create!(author: author, content: "Published deleted", status: "published", deleted_at: Time.now)
        draft_active = Article.create!(author: author, content: "Draft active", status: "draft")
        draft_deleted = Article.create!(author: author, content: "Draft deleted", status: "draft", deleted_at: Time.now)

        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(published_active)
        expect(collected_records).to include(published_deleted)
        expect(collected_records).not_to include(draft_active)
        expect(collected_records).not_to include(draft_deleted)
      end
    end
  end

  describe "polymorphic belongs_to on a model with default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_poly_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Tagging", :taggable
            p.include_associations_for "Article", :author, :taggings
          end
          config.use_preset(:bypass_poly_test)
        end
      end

      it "collects soft-deleted polymorphic targets" do
        deleted_article = Article.create!(author: Author.create!(name: "Author"), content: "Deleted", deleted_at: Time.now)
        tagging = Tagging.create!(taggable: deleted_article, tag_name: "ruby")
        tagging.reload

        expect(tagging.taggable).to be_nil

        collector = described_class.new(tagging)
        collected_records = collector.collect

        expect(collected_records).to include(tagging)
        expect(collected_records).to include(deleted_article)
      end
    end
  end

  describe "has_one association on a model with default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_ho_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Author", :profile
            p.include_associations_for "Profile", :author
          end
          config.use_preset(:bypass_ho_test)
        end
      end

      it "collects soft-deleted has_one targets" do
        author = Author.create!(name: "Has One Test")
        deleted_profile = Profile.create!(author: author, bio: "Gone", deleted_at: Time.now)
        author.reload

        expect(author.profile).to be_nil

        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(author)
        expect(collected_records).to include(deleted_profile)
      end
    end
  end

  describe "has_one :through when the through model has default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_hot_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Author", :profile_detail
            p.include_associations_for "ProfileDetail", :profile
            p.include_associations_for "Profile", :author
          end
          config.use_preset(:bypass_hot_test)
        end
      end

      it "collects profile detail through a soft-deleted profile" do
        author = Author.create!(name: "HOT Test")
        deleted_profile = Profile.create!(author: author, bio: "Gone", deleted_at: Time.now)
        detail = ProfileDetail.create!(profile: deleted_profile, website: "example.com")
        author.reload

        expect(author.profile_detail).to be_nil

        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(author)
        expect(collected_records).to include(detail)
      end
    end
  end

  describe "has_many :through when the through model has default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_through_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Author", :article_comments
            p.include_associations_for "ArticleComment", :article
            p.include_associations_for "Article", :author
          end
          config.use_preset(:bypass_through_test)
        end
      end

      it "collects comments through soft-deleted articles" do
        author = Author.create!(name: "Through Test")
        active_article = Article.create!(author: author, content: "Active")
        deleted_article = Article.create!(author: author, content: "Deleted", deleted_at: Time.now)
        comment_on_active = ArticleComment.create!(article: active_article, body: "Visible")
        comment_on_deleted = ArticleComment.create!(article: deleted_article, body: "Hidden")

        collector = described_class.new(author)
        collected_records = collector.collect

        expect(collected_records).to include(author)
        expect(collected_records).to include(comment_on_active)
        expect(collected_records).to include(comment_on_deleted)
      end
    end
  end

  describe "belongs_to on a model with default_scope" do
    context "when bypass_default_scope is enabled" do
      before do
        RealDataTests.configure do |config|
          config.preset :bypass_bt_test do |p|
            p.bypass_default_scope
            p.include_associations_for "Book", :publisher
            p.include_associations_for "Publisher", :books
          end
          config.use_preset(:bypass_bt_test)
        end
      end

      it "collects soft-deleted belongs_to targets" do
        deleted_publisher = Publisher.unscoped.create!(name: "Gone Publishing", deleted_at: Time.now)
        book = Book.create!(publisher: deleted_publisher, title: "My Book")
        book.reload

        expect(book.publisher).to be_nil

        collector = described_class.new(book)
        collected_records = collector.collect

        expect(collected_records).to include(book)
        expect(collected_records).to include(deleted_publisher)
      end
    end
  end
end
