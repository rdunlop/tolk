require 'test_helper'
require 'fileutils'

class SyncTester
  include Tolk::Sync
  include Tolk::Import
end

class SyncTest < ActiveSupport::TestCase
  def setup
    Tolk::Locale.delete_all
    Tolk::Translation.delete_all
    Tolk::Phrase.delete_all

    Tolk::Locale.locales_config_path = Rails.root.join("../locales/sync/")

    I18n.backend.reload!
    I18n.load_path = [Tolk::Locale.locales_config_path + 'en.yml']
    I18n.backend.send :init_translations

    Tolk::Locale.primary_locale(true)
  end

  def test_flat_hash
    data = {'home' => {'hello' => 'hola', 'sidebar' => {'title' => 'something'}}}
    result = Tolk::Locale.send(:flat_hash, data)

    assert_equal 2, result.keys.size
    assert_equal ['home.hello', 'home.sidebar.title'], result.keys.sort
    assert_equal ['hola', 'something'], result.values.sort
  end

  def test_sync_sets_previous_text_for_primary_locale
    SyncTester.expects(:load_translations).returns({"hello_world" => "Hello World"}).at_least_once
    en = Tolk::Locale.find_by(:name => 'en')
    SyncTester.expects(:primary_locale).returns(en).at_least_once
    #SyncTester.expects(:locales_config_path).returns(Rails.root.join("../locales/sync/")).at_least_once
    #SyncTester.expects(:primary_locale_name).returns("English").at_least_once
    SyncTester.sync!
    #Tolk::Locale.sync!

    # Change 'Hello World' to 'Hello Super World'
    SyncTester.expects(:load_translations).returns({"hello_world" => "Hello Super World"}).at_least_once
    SyncTester.sync!

    translation = Tolk::Locale.primary_locale(true).translations.first
    assert_equal 'Hello Super World', translation.text
    assert_equal 'Hello World', translation.previous_text
  end

  def test_sync_from_disk
    SyncTester.expects(:locales_config_path).returns(Rails.root.join("../locales/import/views/")).at_least_once
    primary_locale = Tolk::Locale.find_by(:name => 'en')
    SyncTester.expects(:primary_locale_name).returns("en").at_least_once
    SyncTester.sync_from_disk!

    phrase = Tolk::Phrase.first
    assert_equal 'Welcome to Rails', phrase.translations.where(locale: primary_locale).first.text
    assert_equal 'Bienvenue a Rails',       phrase.translations.where.not(locale: primary_locale).first.text
  end

  def test_sync_from_disk_direct
    hash = { "en" => {"views.index.title"=>"Welcome to Rails"}, "fr" => {"views.index.title"=>"Bienvenue a Rails"}}
    SyncTester.expects(:primary_locale_name).returns("en").at_least_once
    SyncTester.sync_from_disk(hash, "en")

    primary_locale = Tolk::Locale.find_by(:name => 'en')
    phrase = Tolk::Phrase.first
    assert_equal 'Welcome to Rails', phrase.translations.where(locale: primary_locale).first.text
    assert_equal 'Bienvenue a Rails',       phrase.translations.where.not(locale: primary_locale).first.text

    updated_hash = { "en" => {"views.index.title"=>"Welcome to New Rails"}, "fr" => {"views.index.title"=>"Bienvenue a Rails"}}
    SyncTester.sync_from_disk(updated_hash, "en")

    phrase = Tolk::Phrase.first
    english_translation = phrase.translations.where(locale: primary_locale).first
    french_translation = phrase.translations.where.not(locale: primary_locale).first
    assert_equal "Welcome to New Rails", english_translation.text
    assert_equal true, french_translation.primary_updated
  end

  def test_sync_with_changes
    hash = { "en" => {"views.index.title"=>"Welcome to Rails"}, "fr" => {"views.index.title"=>"Bienvenue a Rails"}}
    SyncTester.expects(:primary_locale_name).returns("en").at_least_once
    SyncTester.sync_from_disk(hash, "en")

    primary_locale = Tolk::Locale.find_by(:name => 'en')
    phrase = Tolk::Phrase.first
    english_translation = phrase.translations.where(locale: primary_locale).first
    french_translation = phrase.translations.where.not(locale: primary_locale).first

    french_translation.text = "Updated Bienvenue"
    french_translation.save!

    updated_hash = { "en" => {"views.index.title"=>"Welcome to New Rails"}, "fr" => {"views.index.title"=>"Bienvenue a Rails"}}
    SyncTester.sync_from_disk(updated_hash, "en")

    phrase = Tolk::Phrase.first
    english_translation = phrase.translations.where(locale: primary_locale).first
    french_translation = phrase.translations.where.not(locale: primary_locale).first

    assert_equal "Bienvenue a Rails", french_translation.text
  end

  def test_load_from_disk
    SyncTester.expects(:locales_config_path).returns(Rails.root.join("../locales/import/views/")).at_least_once
    translations = SyncTester.load_translations_from_disk

    assert_equal 2, translations.count
    assert_equal({"en"=>{"views.index.title"=>"Welcome to Rails"}, "fr"=>{"views.index.title"=>"Bienvenue a Rails"}}, translations)
  end

  def test_sync_sets_primary_updated_for_secondary_translations_on_update
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.expects(:load_translations).returns({"hello_world" => "Hello World", 'nested.hello_country' => 'Nested Hello Country'}).at_least_once
    Tolk::Locale.sync!

    phrase1 = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    t1 = spanish.translations.create!(:text => 'hola', :phrase => phrase1)
    phrase2 = Tolk::Phrase.all.detect {|p| p.key == 'nested.hello_country'}
    t2 = spanish.translations.create!(:text => 'nested hola', :phrase => phrase2)

    # Change 'Hello World' to 'Hello Super World'. But don't change nested.hello_country
    Tolk::Locale.expects(:load_translations).returns({'hello_world' => 'Hello Super World', 'nested.hello_country' => 'Nested Hello Country'}).at_least_once
    Tolk::Locale.sync!

    t1.reload
    t2.reload

    assert t1.primary_updated?
    assert ! t2.primary_updated?
  end

  def test_sync_marks_translations_for_review_when_the_primary_translation_has_changed
    Tolk::Locale.create!(:name => 'es')

    phrase = Tolk::Phrase.create! :key => 'number.precision'
    phrase.translations.create!(:text => "1", :locale => Tolk::Locale.where(name: "en").first)
    spanish_translation = phrase.translations.create!(:text => "1", :locale => Tolk::Locale.where(name: "es").first)

    Tolk::Locale.expects(:load_translations).returns({'number.precision' => "1"}).at_least_once
    Tolk::Locale.sync! and spanish_translation.reload
    assert spanish_translation.up_to_date?

    Tolk::Locale.expects(:load_translations).returns({'number.precision' => "2"}).at_least_once
    Tolk::Locale.sync! and spanish_translation.reload
    assert spanish_translation.out_of_date?

    spanish_translation.text = "2"
    spanish_translation.save! and spanish_translation.reload
    assert spanish_translation.up_to_date?

    Tolk::Locale.expects(:load_translations).returns({'number.precision' => 2}).at_least_once
    Tolk::Locale.sync! and spanish_translation.reload
    assert spanish_translation.up_to_date?

    Tolk::Locale.expects(:load_translations).returns({'number.precision' => 1}).at_least_once
    Tolk::Locale.sync! and spanish_translation.reload
    assert spanish_translation.out_of_date?
  end

  def test_sync_creates_locale_phrases_translations
    Tolk::Locale.expects(:load_translations).returns({'hello_world' => 'Hello World', 'nested.hello_country' => 'Nested Hello Country'}).at_least_once
    Tolk::Locale.sync!

    # Created by sync!
    primary_locale = Tolk::Locale.where(name: Tolk::Locale.primary_locale_name).first!

    assert_equal ["Hello World", "Nested Hello Country"], primary_locale.translations.map(&:text).sort
    assert_equal ["hello_world", "nested.hello_country"], Tolk::Phrase.all.map(&:key).sort
  end

  def test_sync_deletes_stale_translations_for_secondary_locales_on_delete_all
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.expects(:load_translations).returns({'hello_world' => 'Hello World', 'nested.hello_country' => 'Nested Hello Country'}).at_least_once
    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting all the translations
    Tolk::Locale.expects(:load_translations).returns({}).at_least_once
    Tolk::Locale.sync!

    assert_equal 0, Tolk::Phrase.count
    assert_equal 0, Tolk::Translation.count

    assert_raises(ActiveRecord::RecordNotFound) { hola.reload }
  end

  def test_sync_deletes_stale_translations_for_secondary_locales_on_delete_some
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.expects(:load_translations).returns({'hello_world' => 'Hello World', 'nested.hello_country' => 'Nested Hello Country'}).at_least_once
    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting 'hello_world'
    Tolk::Locale.expects(:load_translations).returns({'nested.hello_country' => 'Nested Hello World'}).at_least_once
    Tolk::Locale.sync!

    assert_equal 1, Tolk::Phrase.count
    assert_equal 1, Tolk::Translation.count
    assert_equal 0, spanish.translations.count

    assert_raises(ActiveRecord::RecordNotFound) { hola.reload }
  end

  def test_sync_handles_deleted_keys_and_updated_translations
    Tolk::Locale.sync!

    # Mimic deleting 'nested.hello_country' and updating 'hello_world'
    Tolk::Locale.expects(:load_translations).returns({"hello_world" => "Hello Super World"}).at_least_once
    Tolk::Locale.sync!

    primary_locale = Tolk::Locale.where(name: Tolk::Locale.primary_locale_name).first!

    assert_equal ['Hello Super World'], primary_locale.translations.map(&:text)
    assert_equal ['hello_world'], Tolk::Phrase.all.map(&:key).sort
  end

  def test_sync_doesnt_mess_with_existing_translations
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.expects(:load_translations).returns({"hello_world" => "Hello Super World"}).at_least_once
    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting 'nested.hello_country' and updating 'hello_world'
    Tolk::Locale.expects(:load_translations).returns({"hello_world" => "Hello Super World"}).at_least_once
    Tolk::Locale.sync!

    hola.reload
    assert_equal 'hola', hola.text
  end

  def test_sync_array_values
    spanish = Tolk::Locale.create!(:name => 'es')

    data = {"weekend" => ['Friday', 'Saturday', 'Sunday']}
    Tolk::Locale.expects(:load_translations).returns(data).at_least_once
    Tolk::Locale.sync!

    assert_equal 1, Tolk::Locale.primary_locale.translations.count

    translation = Tolk::Locale.primary_locale.translations.first
    assert_equal data['weekend'], translation.text

    yaml = ['Saturday', 'Sunday'].to_yaml
    spanish_weekends = spanish.translations.create!(:text => yaml, :phrase => Tolk::Phrase.first)
    assert_equal Tolk::YAML.load(yaml), spanish_weekends.text
  end

  def test_dump_all_after_sync
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    spanish.translations.create!(:text => 'hola', :phrase => phrase)

    tmpdir = Rails.root.join("../../tmp/sync/locales")
    FileUtils.mkdir_p(tmpdir)
    Tolk::Locale.dump_all(tmpdir)

    spanish_file = "#{tmpdir}/es.yml"
    data = Tolk::YAML.load_file(spanish_file)['es']
    assert_equal ['hello_world'], data.keys
    assert_equal 'hola', data['hello_world']
  ensure
    FileUtils.rm_f(tmpdir)
  end

  def test_dump_locale_after_sync
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    spanish.translations.create!(:text => 'hola', :phrase => phrase)

    tmpdir = Rails.root.join("../../tmp/sync/locales")
    FileUtils.mkdir_p(tmpdir)
    Tolk::Locale.dump_yaml('es', tmpdir)

    spanish_file = "#{tmpdir}/es.yml"
    data = Tolk::YAML.load_file(spanish_file)['es']
    assert_equal ['hello_world'], data.keys
    assert_equal 'hola', data['hello_world']
  ensure
    FileUtils.rm_f(tmpdir)
  end
end
