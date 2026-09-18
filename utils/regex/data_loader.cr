require "http"
require "./sequence_regex"

class Emoji::Regex::DataLoader
  property :data_lines, :sequences_lines, :zwj_sequences_lines, :variation_sequences_lines

  @data_lines : Array(String)
  @sequences_lines : Array(String)
  @zwj_sequences_lines : Array(String)
  @variation_sequences_lines : Array(String)

  BASE_URL = "https://unicode.org"
  # <codepoint(s)> ; <property> # <comments>
  DATA_REGEX = /(?<codepoint>[0-9A-F.]+)\s+;\s+(?<property>\S+)\s*?\#[^\S]*(?<comments>.*)/
  # code_point(s) ; type_field ; description # comments
  SEQUENCES_REGEX = /^(?<codepoints>[0-9A-F ]+?)\s*?;\s+?(?<type_field>.+?)\s*?;(\s+)?(?<description>.+?)\s*?#\s*?(?<comments>.*)/

  def initialize
    @data_lines = read_lines_from_file("/Public/18.0.0/ucd/emoji/emoji-data.txt")
    @variation_sequences_lines = read_lines_from_file("/Public/18.0.0/ucd/emoji/emoji-variation-sequences.txt")
    @sequences_lines = read_lines_from_file("/Public/18.0.0/emoji/emoji-sequences.txt")
    @zwj_sequences_lines = read_lines_from_file("/Public/18.0.0/emoji/emoji-zwj-sequences.txt")
  end

  def data_codepoints_regex
    data_codepoints = [] of Int32
    data_lines.each do |line|
      if m = DATA_REGEX.match(line)
        if ["Emoji_Presentation"].includes?(m["property"])
          if range = /(.+)\.\.(.*)/.match(m["codepoint"])
            data_codepoints.concat(range[1].to_i(16)..range[2].to_i(16))
          else
            data_codepoints << m["codepoint"].to_i(16)
          end
        end
      end
    end

    character_class_regex(data_codepoints)
  end

  def emoji_zwj_sequences_regex
    sequences = [] of Array(Int32)
    zwj_sequences_lines.each do |line|
      if m = SEQUENCES_REGEX.match(line)
        # Preserve the existing acceptance of omitted emoji variation selectors.
        variants = [[] of Int32]
        m["codepoints"].split.each do |hex|
          codepoint = hex.to_i(16)
          extended = variants.map { |variant| variant + [codepoint] }
          variants = codepoint == 0xFE0F ? extended + variants : extended
        end
        sequences.concat(variants)
      end
    end
    sequence_regex(sequences)
  end

  def emoji_variation_sequences_regex
    variation_selector = "\\\\\\\\x{FE0F}"

    emoji_variations = [] of Int32
    text_variations = [] of Int32

    variation_sequences_lines.each do |line|
      if m = SEQUENCES_REGEX.match(line)
        if m["type_field"] == "emoji style"
          codepoints = m["codepoints"].split

          if ascii?(codepoints[0])
            text_variations << codepoints[0].to_i(16)
          else
            emoji_variations << codepoints[0].to_i(16)
          end
        end
      end
    end

    emoji_regex = character_class_regex(emoji_variations)
    text_regex = character_class_regex(text_variations)

    "(?:#{emoji_regex}#{variation_selector}?)|(?:#{text_regex}#{variation_selector})"
  end

  def emoji_keycap_sequences_regex
    enclosing_keycap = ["FE0F", "20E3"]
    enclosing_keycap_regex = enclosing_keycap.map { |codepoint| escape_hexadecimal(codepoint) }.join

    keycaps = [] of Int32

    sequences_lines.each do |line|
      if m = SEQUENCES_REGEX.match(line)
        if ["Emoji_Keycap_Sequence"].includes?(m["type_field"])
          keycaps << m["codepoints"].split(2).first.to_i(16)
        end
      end
    end

    keycaps_regex = character_class_regex(keycaps)

    "(?:#{keycaps_regex}#{enclosing_keycap_regex})"
  end

  # http://www.unicode.org/reports/tr51/#def_emoji_tag_sequence
  def emoji_tag_sequence_regex
    tag_base = ["1F3F4", "E0067", "E0062"]
    tag_term = ["E007F"]
    tag_specs = [] of Array(String)

    sequences_lines.each do |line|
      if m = SEQUENCES_REGEX.match(line)
        if ["RGI_Emoji_Tag_Sequence"].includes?(m["type_field"])
          codepoints = m["codepoints"].split
          tag_spec = codepoints[3..-2]
          tag_specs << tag_spec
        end
      end
    end

    tag_base_regex = tag_base.map { |codepoint| escape_hexadecimal(codepoint) }.join
    tag_term_regex = tag_term.map { |codepoint| escape_hexadecimal(codepoint) }.join

    tag_spec_array = [] of String
    tag_specs.each do |tag|
      tag_spec_array << tag.map { |codepoint| escape_hexadecimal(codepoint) }.join
    end

    tag_spec_regex = tag_spec_array.join("|")

    "(?:#{tag_base_regex}(?:#{tag_spec_regex})#{tag_term_regex})"
  end

  def emoji_sequences_regex
    sequences = [] of Array(Int32)
    sequences_lines.each do |line|
      if m = SEQUENCES_REGEX.match(line)
        if ["RGI_Emoji_Flag_Sequence", "RGI_Emoji_Modifier_Sequence"].includes?(m["type_field"])
          sequences << m["codepoints"].split.map(&.to_i(16))
        end
      end
    end
    sequence_regex(sequences)
  end

  private def sequence_regex(sequences)
    # The generated pattern passes through two macro string literals.
    Emoji::SequenceRegex.generate(sequences).gsub("\\") { "\\" * 4 }
  end

  private def character_class_regex(codepoints)
    Emoji::SequenceRegex.character_class(codepoints).gsub("\\") { "\\" * 4 }
  end

  private def read_lines_from_file(filename) : Array(String)
    response = HTTP::Client.get(BASE_URL + filename)
    response.body.lines
  end

  def escape_hexadecimal(codepoint)
    if codepoint == "FE0F"
      "\\\\\\\\x{#{codepoint}}?"
    else
      "\\\\\\\\x{#{codepoint}}"
    end
  end

  def ascii?(codepoint)
    codepoint.to_i(16).chr.ascii?
  end
end

data_loader = Emoji::Regex::DataLoader.new

emoji_zwj_sequences_regex = data_loader.emoji_zwj_sequences_regex
emoji_sequences_regex = data_loader.emoji_sequences_regex
emoji_tag_sequence_regex = data_loader.emoji_tag_sequence_regex
emoji_keycap_sequences_regex = data_loader.emoji_keycap_sequences_regex
emoji_variation_sequences_regex = data_loader.emoji_variation_sequences_regex
data_codepoints_regex = data_loader.data_codepoints_regex

print "#{emoji_zwj_sequences_regex}\
      |#{emoji_sequences_regex}\
      |#{emoji_tag_sequence_regex}\
      |#{emoji_keycap_sequences_regex}\
      |#{emoji_variation_sequences_regex}\
      |#{data_codepoints_regex}"
