class Emoji::SequenceRegex
  def self.generate(sequences : Array(Array(Int32))) : String
    terminal = sequences.any?(&.empty?)
    children = {} of Int32 => Array(Array(Int32))
    sequences.each do |sequence|
      next if sequence.empty?
      (children[sequence.first] ||= [] of Array(Int32)) << sequence[1..]
    end

    # Equal suffixes can share a character class, even at internal nodes.
    suffixes = {} of String => Array(Int32)
    children.keys.sort!.each do |codepoint|
      suffix = generate(children[codepoint])
      (suffixes[suffix] ||= [] of Int32) << codepoint
    end
    branches = suffixes.map do |suffix, codepoints|
      character_class(codepoints) + suffix
    end
    return "" if branches.empty?

    pattern = branches.size == 1 ? branches.first : "(?:#{branches.join("|")})"
    # A terminal node is optional, but greedy: consume the longest sequence.
    return pattern unless terminal
    # Alternatives are already grouped; a character or character class is one atom.
    if branches.size > 1 || suffixes.has_key?("")
      "#{pattern}?"
    else
      "(?:#{pattern})?"
    end
  end

  def self.character_class(codepoints : Array(Int32)) : String
    sorted = codepoints.sort.uniq!
    return escape(sorted.first) if sorted.size == 1

    ranges = [] of String
    first = last = sorted.first
    sorted.skip(1).each do |codepoint|
      if codepoint == last + 1
        last = codepoint
      else
        ranges << range(first, last)
        first = last = codepoint
      end
    end
    ranges << range(first, last)
    "[#{ranges.join}]"
  end

  private def self.range(first, last) : String
    return escape(first) if first == last
    return escape(first) + escape(last) if last == first + 1
    "#{escape(first)}-#{escape(last)}"
  end

  private def self.escape(codepoint) : String
    "\\x{#{codepoint.to_s(16).upcase}}"
  end
end
