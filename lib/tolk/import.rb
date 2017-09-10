module Tolk
  module Import
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods

      def import_secondary_locales
        locales = Dir.entries(self.locales_config_path)

        locale_block_filter = Proc.new {
          |l| ['.', '..'].include?(l) ||
            !l.ends_with?('.yml') ||
            l.match(/(.*\.){2,}/) # reject files of type xxx.en.yml
        }
        locales = locales.reject(&locale_block_filter).map {|x| x.split('.').first }
        locales = locales - [Tolk::Locale.primary_locale.name]
        locales.each {|l| import_locale(l) }
      end

      def import_locale(locale_name)
        locale = Tolk::Locale.where(name: locale_name).first_or_create
        data = locale.read_locale_file
        return unless data

        import_locale_data(locale_name, data)
      end

      def import_locale_data(locale_name, data)
        locale = Tolk::Locale.where(name: locale_name).first_or_create
        phrases = Tolk::Phrase.all

        data.each do |key, value|
          phrase = phrases.detect {|p| p.key == key}

          if phrase
            translation = locale.translations.where(phrase: phrase).first || locale.translations.build(:phrase => phrase)
            translation.text = value
            if translation.changed? && !translation.new_record?
              puts "[WARN] Key '#{key}' from '#{locale_name}' could not be saved because it is different in the DB"
            end

            translation.save! if translation.changed?
          else
            puts "[ERROR] Key '#{key}' was found in '#{locale_name}' but #{Tolk::Locale.primary_language_name} translation is missing"
          end
        end
      end

    end

    def read_locale_file
      locale_file = "#{self.locales_config_path}/#{self.name}.yml"
      raise "Locale file #{locale_file} does not exists" unless File.exist?(locale_file)

      puts "[INFO] Reading #{locale_file} for locale #{self.name}"
      begin
        self.class.flat_hash(Tolk::YAML.load_file(locale_file)[self.name])
      rescue
        puts "[ERROR] File #{locale_file} expected to declare #{self.name} locale, but it does not. Skipping this file."
        nil
      end

    end

  end
end
