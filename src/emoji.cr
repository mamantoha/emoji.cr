require "./emoji/*"

module Emoji
  VERSION                   = "0.3.1"
  EMOJI_TAG_SEQUENCE_REGEXP = "(?:\\x{1F3F4}\\x{E0067}\\x{E0062}(?:\\x{E0065}\\x{E006E}\\x{E0067}|\\x{E0073}\\x{E0063}\\x{E0074}|\\x{E0077}\\x{E006C}\\x{E0073})\\x{E007F})"
  SIMPLE_EMOJI_REGEX        = "[\\x{1f000}-\\x{1ffff}\\x{2049}-\\x{3299}\\x{a9}\\x{2a}\\x{ae}\\x{fe0f}\\x{203c}\\x{200d}]+|[0-9#]\\x{fe0f}\\x{20e3}"
  EMOJI_REGEX               = Regex.new("#{EMOJI_TAG_SEQUENCE_REGEXP}|#{SIMPLE_EMOJI_REGEX}")

  enum RegexType
    Simple
    Generated
  end

  @@map = Emoji::EMOJI_MAP

  def self.emojize(text : String)
    text.scan(/:[^(: )]+?:/).map { |data| data[0] }
      .uniq!
      .each do |name|
        code = @@map[name]?
        text = text.gsub(name, code) if code
      end
    text
  end

  def self.sanitize(text : String, regex : RegexType = :simple)
    case regex
    when .simple?    then text.gsub(EMOJI_REGEX, "")
    when .generated? then text.gsub(GENERATED_EMOJI_REGEX, "")
    end
  end
end
