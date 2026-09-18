class Emoji::SequenceRegex
  def self.generate(sequences : Array(Array(Int32))) : String
    # Pull a shared trailing sequence outside the trie before factoring prefixes.
    suffix_size = sequences.min_of?(&.size) || 0
    while suffix_size > 0
      suffix = sequences.first[-suffix_size..]
      break if sequences.all? { |sequence| sequence[-suffix_size..] == suffix }
      suffix_size -= 1
    end
    if suffix_size > 0
      prefixes = sequences.map { |sequence| sequence[0, sequence.size - suffix_size] }
      suffix = sequences.first[-suffix_size..].map { |codepoint| escape(codepoint) }.join
      return generate(prefixes) + suffix
    end

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
    branches = suffixes.map do |continuation, codepoints|
      character_class(codepoints) + continuation
    end
    return "" if branches.empty?

    branches = factor_suffixes(branches)

    pattern = branches.size == 1 ? branches.first : "(?:#{branches.join("|")})"
    # A terminal node is optional, but greedy: consume the longest sequence.
    return pattern unless terminal
    # Alternatives are already grouped; a character or character class is one atom.
    if branches.size > 1 || (suffixes.size == 1 && suffixes.has_key?(""))
      "#{pattern}?"
    else
      "(?:#{pattern})?"
    end
  end

  private def self.factor_suffixes(branches : Array(String)) : Array(String)
    # Siblings start with disjoint character sets, so regrouping preserves priority.
    # Peel complete trailing atoms only; grouped expressions remain in the prefix.
    loop do
      candidates = {} of String => Array(Int32)
      branches.each_with_index do |branch, index|
        if tail = /(?:\\x\{[0-9A-F]+\}\??|\[[^\]]+\]\??)+$/.match(branch)
          suffix = tail[0]
          until suffix.empty?
            (candidates[suffix] ||= [] of Int32) << index
            suffix = suffix.sub(/\A(?:\\x\{[0-9A-F]+\}\??|\[[^\]]+\]\??)/, "")
          end
        end
      end

      saving = 0
      selected = [] of Int32
      replacement = ""
      candidates.each do |suffix, indices|
        next if indices.size < 2
        prefixes = indices.map { |index| branches[index].rchop(suffix) }
        optional = prefixes.any?(&.empty?)
        prefixes.reject!(&.empty?)
        prefix = prefixes.size == 1 ? prefixes.first : "(?:#{prefixes.join("|")})"
        prefix = "(?:#{prefix})?" if optional
        candidate = prefix + suffix
        # Include separators and new groups when deciding whether factoring pays off.
        reduction = indices.sum { |index| branches[index].bytesize } + indices.size - 1 - candidate.bytesize
        if reduction > saving
          saving = reduction
          selected = indices
          replacement = candidate
        end
      end
      return branches if saving == 0

      branches = branches.map_with_index do |branch, index|
        index == selected.first ? replacement : (selected.includes?(index) ? "" : branch)
      end.reject(&.empty?)
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
