module Tolk
  class ExportToFiles
    attr_reader :name, :data, :destination, :enable_debug

    def initialize(args)
      @name = args.fetch(:name, '')
      @data = args.fetch(:data, {})
      @destination = args.fetch(:destination, self.class.dump_path)
    end

    def dump
      new_files = []
      translations_files = Dir[Pathname.new(destination).join("**", "*.{rb,yml}")]
      translations_files.each do |translation_file|
        translations = Tolk::YAML.load_file(translation_file)
        primary_language_translations = translations[Tolk::Locale.primary_locale_name] || {}

        filename = translation_file.split("/").last
        directory = translation_file.split("/") - [translation_file.split("/").last]

        matched = filename.match(/(.*)\.([a-z][a-z])\.yml/)
        if matched.nil?
          matched = filename.match(/(.*)\.yml/)
          file_base = matched[1]
          file_language = Tolk::Locale.primary_locale_name
          other_languages = data.keys
        else
          file_base = matched[1]
          file_language = matched[2]
          next unless file_language == Tolk::Locale.primary_locale_name
          other_languages = data.keys - [Tolk::Locale.primary_locale_name]
        end

        other_languages.each do |language|
          matching_data = match(primary_language_translations, data[language])
          debug "primary: #{primary_language_translations}"
          debug "target: #{data[language]}"
          debug "matching_data: #{matching_data}"
          next unless matching_data.present?
          file_data = { language => matching_data }
          language_file_name = (directory + ["#{file_base}.#{language}.yml"]).join("/")

          if !File.exists? language_file_name
            new_files += [language_file_name]
          end

          File.open(language_file_name, "w+") do |file|
            file.write(Tolk::YAML.dump(file_data))
          end
        end
      end
      I18n.config.load_path += new_files
    end

    def match(original_hash, new_hash)
      return nil if original_hash.nil? || new_hash.nil?
      new_hash = new_hash.select { |k, _| original_hash.include? k }
      new_hash.each do |k, v|
        if v.is_a?(Hash)
          new_hash[k] = match(original_hash[k], v)
        end
      end
      return nil if new_hash.keys.none? {|key| new_hash[key].present? }
      new_hash
    end

    def debug(str)
      puts str if enable_debug
    end

    class << self
      def dump(args)
        new(args).dump
      end

      def dump_path
        Tolk::Locale._dump_path
      end
    end
  end
end
