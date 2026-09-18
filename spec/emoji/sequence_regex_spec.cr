require "../spec_helper"
require "../../utils/regex/sequence_regex"

describe Emoji::SequenceRegex do
  it "factors prefixes and combines identical suffixes into ranges" do
    sequences = ["ax!", "ay!", "az!", "bx!", "by!", "bz!"].map(&.codepoints)
    Emoji::SequenceRegex.generate(sequences).should eq "[\\x{61}\\x{62}][\\x{78}-\\x{7A}]\\x{21}"
  end

  it "prefers complete sequences over their prefixes" do
    sequences = ["a", "ab", "abc", "abd", "ax"].map(&.codepoints)
    regex = Regex.new(Emoji::SequenceRegex.generate(sequences))
    "abc abd ab ax a".scan(regex).map(&.[0]).should eq ["abc", "abd", "ab", "ax", "a"]
  end

  it "preserves exactly the supplied finite language" do
    words = ["a", "ab", "abc", "ac", "bac", "bbc", "bcc", "cba"]
    regex = Regex.new("\\A(?:#{Emoji::SequenceRegex.generate(words.map(&.codepoints))})\\z")
    candidates = [""]
    4.times do
      candidates += candidates.flat_map { |prefix| ["a", "b", "c"].map { |char| prefix + char } }
    end
    candidates.uniq.each do |candidate|
      regex.matches?(candidate).should eq words.includes?(candidate)
    end
  end
end
