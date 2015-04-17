module Tolk
  module Sync
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def sync!
        sync_phrases(load_translations)
      end

      def sync_from_disk!
        load_translations_from_disk
      end

      def load_translations_from_disk
        translations_files = Dir[self.locales_config_path.join("**", "*.{rb,yml}")]
        translations_files.each do |translation_file|
          translations = Tolk::YAML.load_file(translation_file)
          languages = translations.keys

          locale_name = "Robin FAKE"
          count = 0

          languages.each do |language|
            phrases = Tolk::Phrase.all
            locale = Tolk::Locale.where(name: language).first_or_create
            language_data = flat_hash(translations[language])

            language_data.each do |key, value|
              phrase = phrases.detect {|p| p.key == key}

              if phrase
                translation = locale.translations.new(:text => value, :phrase => phrase)
                if translation.save
                  count = count + 1
                elsif translation.errors[:variables].present?
                  puts "[WARN] Key '#{key}' from '#{locale_name}.yml' could not be saved: #{translation.errors[:variables].first}"
                end
              else
                if Tolk::Locale.primary_locale_name == language
                  phrase = Tolk::Phrase.create!(:key => key)
                  translation = locale.translations.new(:text => value, :phrase => phrase)
                  if translation.save
                    count = count + 1
                  elsif translation.errors[:variables].present?
                    puts "[WARN] Key '#{key}' from '#{locale_name}.yml' could not be saved: #{translation.errors[:variables].first}"
                  end
                else
                  puts "[ERROR] Key '#{key}' was found in '#{locale_name}.yml' but #{Tolk::Locale.primary_language_name} translation is missing"
                end
              end
            end
          end
          puts "[INFO] Imported #{count} keys from #{translation_file}"
        end
        #translations_files = filter_blocked_files(translation_files)
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
        if File.exists?(primary_file)
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

      def sync_phrases(translations)
        primary_locale = self.primary_locale

        # Handle deleted phrases
        translations.present? ? Tolk::Phrase.destroy_all(["tolk_phrases.key NOT IN (?)", translations.keys]) : Tolk::Phrase.destroy_all

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
