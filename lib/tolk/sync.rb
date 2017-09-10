module Tolk
  module Sync
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def sync!
        sync_phrases(load_translations, primary_locale)
      end

      def sync_from_disk!
        languages_and_translations = load_translations_from_disk
        sync_from_disk(languages_and_translations, primary_locale_name)
      end

      def sync_from_disk(languages_and_translations, primary_locale_name)
        primary_locale = Tolk::Locale.where(name: self.primary_locale_name).first_or_create
        sync_phrases(languages_and_translations[primary_locale_name], primary_locale)

        (languages_and_translations.keys - [primary_locale_name]).each do |secondary_locale|
          self.import_locale_data(secondary_locale, languages_and_translations[secondary_locale])
        end
      end

      # Load translations from multiple disk files, and return the resulting super-hash
      #
      # Returns: { "en" => { "key" => "value", "key2" => "value"},
      #            "fr" => { "key" => "valu" , "key2" => "valu2"}}
      def load_translations_from_disk
        translations_files = Dir[self.locales_config_path.join("**", "*.{rb,yml}")]
        all_language_translations = {}
        translations_files.each do |translation_file|
          translations = Tolk::YAML.load_file(translation_file)
          all_language_translations.deep_merge!(translations)
        end

        result = {}
        all_language_translations.keys.each do |language|
          result[language] = flat_hash(all_language_translations[language])
        end
        result
      end

      def load_translations
        if Tolk.config.exclude_gems_token
          # bypass default init_translations
          I18n.backend.reload! if I18n.backend.initialized?
          I18n.backend.instance_variable_set(:@initialized, true)
          translations_files = Dir[Rails.root.join('config', 'locales', "*.{rb,yml}")]

          if Tolk.config.block_xxx_en_yml_locale_files
            locale_block_filter = Proc.new {
              |l| ['.', '..'].include?(l) ||
                !l.ends_with?('.yml') ||
                l.split("/").last.match(/(.*\.){2,}/) # reject files of type xxx.en.yml
            }
            translations_files =  translations_files.reject(&locale_block_filter)
          end

          I18n.backend.load_translations(translations_files)
        else
          I18n.backend.send :init_translations unless I18n.backend.initialized? # force load
        end
        translations = flat_hash(I18n.backend.send(:translations)[primary_locale.name.to_sym])
        filter_out_i18n_keys(translations.merge(read_primary_locale_file))
      end

      def read_primary_locale_file
        primary_file = "#{self.locales_config_path}/#{self.primary_locale_name}.yml"
        if File.exist?(primary_file)
          flat_hash(Tolk::YAML.load_file(primary_file)[self.primary_locale_name])
        else
          {}
        end
      end

      def flat_hash(data, prefix = '', result = {})
        data.each do |key, value|
          current_prefix = prefix.present? ? "#{prefix}.#{key}" : key

          if !value.is_a?(Hash) || Tolk::Locale.pluralization_data?(value)
            result[current_prefix] = value.respond_to?(:stringify_keys) ? value.stringify_keys : value
          else
            flat_hash(value, current_prefix, result)
          end
        end

        result.stringify_keys
      end

      private

      def sync_phrases(translations, primary_locale)
        # Handle deleted phrases
        translations.present? ? Tolk::Phrase.where(["tolk_phrases.key NOT IN (?)", translations.keys]).destroy_all : Tolk::Phrase.destroy_all

        phrases = Tolk::Phrase.all

        translations.each do |key, value|
          next if value.is_a?(Proc)
          # Create phrase and primary translation if missing
          existing_phrase = phrases.detect {|p| p.key == key} || Tolk::Phrase.create!(:key => key)
          translation = existing_phrase.translations.primary || primary_locale.translations.build(:phrase_id => existing_phrase.id)
          translation.text = value

          if translation.changed? && !translation.new_record?
            # Set the primary updated flag if the primary translation has changed and it is not a new record.
            existing_phrase.translations.where(Tolk::Translation.arel_table[:locale_id].not_eq(primary_locale.id)).update_all({ :primary_updated => true })
          end

          translation.primary = true
          translation.save!
        end
      end

      def filter_out_i18n_keys(flat_hash)
        flat_hash.reject { |key, value| key.starts_with? "i18n" }
      end
    end
  end
end
