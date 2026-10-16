defmodule Llamex.Analysis.Prose do
  @moduledoc """
  Pattern scanner for text that machines write and humans do not.

  The pattern classes come from the ASD-STE100 hook that checks chat
  output and from the nollm rule list. This module applies the same
  classes to text in source files.
  """

  @type finding :: %{class: String.t(), match: String.t()}
  @type line :: %{line: pos_integer(), text: String.t()}
  @type shape_finding :: %{line: pos_integer(), class: String.t(), match: String.t()}

  # Talk that has a meaning only while the change is under review. The
  # list is the nollm list:
  # https://github.com/NullVoxPopuli/nollm/blob/main/src/rules.js
  @review_talk [
    "as requested",
    "as discussed",
    "per the discussion",
    "per our discussion",
    "per the review",
    "per review",
    "per feedback",
    "based on feedback",
    "review feedback",
    "review comment",
    "review comments",
    "addressing feedback",
    "addresses feedback",
    "addressed feedback",
    "requested changes",
    "code review",
    "reviewer",
    "reviewers",
    "this pr",
    "this mr",
    "pr description",
    "pull request",
    "merge request",
    "this commit",
    "this diff",
    "this change",
    "this refactor",
    "the refactor",
    "this migration",
    "this upgrade",
    "the upgrade",
    "after upgrading",
    "before upgrading",
    "since upgrading",
    "version bump",
    "this bump",
    "cherry-picked",
    "cherry picked",
    "backported",
    "rebased",
    "merge conflict",
    "merge conflicts",
    "work in progress",
    "wip",
    "no longer",
    "used to be",
    "used to use",
    "used to return",
    "the old implementation",
    "the old version",
    "the old code",
    "the old approach",
    "the old way",
    "updated to",
    "changed to",
    "instead of the old",
    "instead of the previous",
    "we removed",
    "we replaced",
    "we migrated",
    "we switched",
    "now uses",
    "now returns",
    "now handles",
    "now lives",
    "moved to",
    "never worked",
    "wasn't working",
    "was not working",
    "weren't working",
    "were not working",
    "didn't work before",
    "did not work before",
    "stopped working",
    "was failing",
    "were failing",
    "started failing",
    "kept failing",
    "on the main branch",
    "on the master branch",
    "compared to main",
    "compared to master",
    "no behavior change",
    "no behaviour change",
    "no functional change",
    "no functional changes",
    "no-op change",
    "behavior is unchanged",
    "behaviour is unchanged",
    "behavior unchanged",
    "behaviour unchanged",
    "no change in behavior",
    "no change in behaviour",
    "same as before",
    "same behavior as before",
    "same behaviour as before",
    "behaves as before",
    "behaves the same",
    "works the same",
    "functionally equivalent",
    "functionally identical",
    "preserves behavior",
    "preserves behaviour",
    "preserve behavior",
    "preserve behaviour",
    "preserves existing behavior",
    "preserves existing behaviour",
    "existing behavior",
    "existing behaviour",
    "unchanged from",
    "nothing to disable",
    "nothing to turn off",
    "nothing to uninstall",
    "nothing to revert",
    "nothing to opt out of",
    "no need to disable",
    "no need to turn off",
    "no need to uninstall",
    "no need to revert",
    "keeping it off",
    "keeping it on",
    "keeping this off",
    "keeping this on",
    "keeping it disabled",
    "keeping it enabled",
    "keeping this disabled",
    "keeping this enabled",
    "keep it off",
    "keep this off",
    "kept as is",
    "kept as-is",
    "left as is",
    "left as-is",
    "leave as is",
    "leave as-is",
    "leaving as is",
    "leaving as-is",
    "left in place",
    "left untouched",
    "left alone",
    "leaving this alone",
    "not touching",
    "didn't touch",
    "did not touch",
    "for now",
    "out of scope",
    "scope of this",
    "follow-up pr",
    "follow up pr",
    "in a follow-up",
    "in a follow up",
    "as a follow-up",
    "as a follow up",
    "separate pr",
    "later pr",
    "future pr",
    "another pr",
    "next pr",
    "will be removed",
    "can be removed",
    "to be removed",
    "should be removed",
    "safe to remove",
    "safe to delete",
    "can be deleted",
    "will be deleted",
    "remove this once",
    "remove this after",
    "remove this when",
    "delete this once",
    "delete this after",
    "clean up later",
    "cleanup later",
    "clean this up later",
    "will clean up",
    "will be cleaned up",
    "quick fix",
    "quick hack",
    "quick and dirty",
    "band-aid",
    "bandaid",
    "band aid",
    "stopgap",
    "stop-gap",
    "stop gap",
    "hotfix",
    "hot fix",
    "tested locally",
    "verified locally",
    "confirmed locally",
    "works locally",
    "tested with",
    "tested on",
    "tested against",
    "verified with",
    "confirmed with",
    "ci passes",
    "passes ci",
    "ci is green",
    "ci was failing",
    "ci fails",
    "ci failed",
    "i tested",
    "i verified",
    "i checked",
    "i confirmed",
    "i tried",
    "i went with",
    "i chose",
    "i opted",
    "i decided",
    "i ended up",
    "i left",
    "i kept",
    "i removed",
    "i replaced",
    "i added",
    "i moved",
    "i renamed",
    "i changed",
    "i updated",
    "i bumped",
    "i couldn't",
    "i could not",
    "i'm not sure",
    "i am not sure",
    "not sure if",
    "not sure why",
    "not sure whether",
    "we tested",
    "we verified",
    "we confirmed",
    "we decided",
    "we went with",
    "we opted",
    "we couldn't",
    "we could not"
  ]

  @error_openers [
    "Cannot",
    "Could not",
    "Couldn't",
    "Unable to",
    "Failed to",
    "Unexpected",
    "Invalid",
    "Expected",
    "Missing",
    "Uncaught",
    "Assertion Failed",
    "Maximum call stack"
  ]

  @code_narration [
    "this function",
    "this method",
    "this class",
    "this component",
    "this helper",
    "this hook",
    "this file",
    "this module",
    "this variable",
    "this constant",
    "this line",
    "loop over",
    "loop through",
    "iterate over",
    "iterate through",
    "check if",
    "checks if",
    "increment",
    "decrement",
    "set the",
    "sets the",
    "get the",
    "gets the",
    "create a new",
    "creates a new",
    "initialize the",
    "initializes the",
    "import the",
    "imports the",
    "define the",
    "defines the",
    "call the",
    "calls the",
    "declare"
  ]

  # A line that ends on one of these words stops in the middle of a
  # phrase. The list is the nollm list.
  @dangling_words ~w(a an the of to in on at by for with from into onto upon over under
                     about across after before between during through toward towards
                     within without against among around beyond per via and or but nor
                     that which who whom whose if when while because although though
                     unless until since whether is are was were has have had its their
                     your our my every)

  # The sentence and paragraph limits come from ASD-STE100. The other
  # limits are the nollm defaults.
  @long_sentence_words 25
  @wall_words 120
  @wall_sentences 6
  @uniform_paragraph_min_words 25
  @uniform_paragraph_spread 1.25
  @uniform_sentence_min_count 4
  @uniform_sentence_min_words 8
  @uniform_sentence_variation 0.2

  @noise [
    # inline code
    ~r/`[^`\n]*`/,
    # URLs
    ~r"https?://\S+"
  ]

  @doc "Removes inline code and URLs from the text."
  @spec strip_noise(String.t()) :: String.t()
  def strip_noise(text) do
    Enum.reduce(@noise, text, &Regex.replace(&1, &2, " "))
  end

  @doc """
  Returns one finding per pattern match in the text.

  The text must be free of noise. Call `strip_noise/1` first.
  """
  @spec scan(String.t()) :: [finding()]
  def scan(text) do
    Enum.flat_map(patterns(), fn {class, regex} ->
      regex
      |> Regex.scan(text, capture: :first)
      |> Enum.map(fn [match] -> %{class: class, match: match} end)
    end)
  end

  # Regex literals stay inside a function. A regex in a module attribute
  # does not compile on OTP 28. Every pattern except the quoted error
  # pattern has the `i` flag. A banned word at the start of a sentence
  # has a capital letter. An error message starts with a capital letter,
  # so the quoted error pattern is case-sensitive.
  defp patterns do
    [
      {"em dash", ~r/—/iu},
      {"semicolon", ~r/;/i},
      {"contraction", ~r/\b\w+n[’']t\b/iu},
      {"contraction", ~r/\b\w+[’'](?:re|ll|ve|m)\b/iu},
      {"contraction", ~r/\b(?:it|that|there|here|what|who|he|she|one|let)[’']s\b/iu},
      {"banned modal", ~r/\b(?:should|would|might|could)\b/i},
      {"banned modal 'may'", ~r/\bmay\b/i},
      {"present perfect", ~r/\b(?:has|have|had)\s+been\b/i},
      {"present perfect", ~r/\b(?:has|have)\s+\w+ed\b/i},
      {"word with no fact",
       ~r/\b(?:simply|seamlessly|seamless|robust|powerful|comprehensive|leverages?|leveraged|utilizes?|utilized|elegant(?:ly)?|effortless(?:ly)?|blazing(?:ly)?|stunning|holistic|battle-tested|world-class|game-chang\w+)\b/i},
      {"latin abbreviation", ~r/\be\.g\.|\bi\.e\./i},
      {"banned phrase", ~r/\bin order to\b|\bprior to\b|\bin the event that\b/i},
      {"filler phrase",
       ~r/\bnot only\b|\bload-bearing\b|\bworth noting\b|\bunder the hood\b|\bheavy lifting\b|\blow-hanging fruit\b|\bdeep[- ]dive\b|\bdelves?\b|\bdelved\b|\bat the end of the day\b|\bboils? down to\b|\bthat (?:being )?said\b|\bneedless to say\b|\brest assured\b|\bkeep in mind\b|\ba breeze\b|\bdouble[- ]check\b|\bdrill down\b/i},
      {"metaphor verb",
       ~r/\b(?:rescues?|rescued|nudges?|nudged|swallows?|swallowed|attacks?|attacked|fights?|fought|rides?|rode|lands?|landed|(?:wires?|wired)(?:\s+\w+){0,3}\s+up|(?:slips?|slipped|gets?|got)\s+through)\b/i},
      {"container verb 'hold'", ~r/\b(?:holds?|held|holding)\b/i},
      {"status verb 'stand'", ~r/\b(?:stands?|stood|standing)\b(?!-)/i},
      {"fact-free adverb",
       ~r/\b(?:honestly|frankly|candidly|obviously|clearly|genuinely)\b|\b(?:to be (?:clear|honest|fair))\b/i},
      {"process narration",
       ~r/\b(?:I stop here|I pause here|I wait for your|I proceed|let me|I(?: will)? go ahead|going ahead and|I will|I need to|now I|now we|here we|first,? we|we now)\b/i},
      {"stalling phrase", ~r/\b(?:wait)\s*--|\b(?:but\s+wait)\b|\b(?:hold\s+on)\b/i},
      {"user validation phrase",
       ~r/\b(?:the\s+user\s+is\s+(?:right|correct))\b|\b(?:you\s+(?:are|were)\s+(?:right|correct))\b/i},
      {"pattern label frame", ~r/\b(?:(?:the\s+)?\w+\s+pattern\s+is)\s*:/i},
      {"self-blame phrase",
       ~r/\b(?:(?:that|this|it)\s+(?:is|was)\s+on\s+me)\b|\b(?:my\s+(?:bad|mistake|fault|error|oversight))\b|\b(?:I\s+apologi[sz]e|apologies|mea\s+culpa)\b/i},
      {"noun metaphor",
       ~r/\b(?:guardrails?|wrinkles?|north star|silver bullet|footguns?|rabbit hole|red flags?|smell test|landmines?|moving parts?|pain points?|ticking time bomb|knobs?|treadmills?|security holes?|failure chain|safety nets?)\b|\b(?:gaps?\s+remains?|gaps?\s+remained|one\s+gap|a\s+gap\s+in|the\s+gap\s+in|coverage\s+gaps?|(?:closes?|closed|fills?|filled|plugs?|plugged)\s+(?:the|a|this|that)\s+gaps?)\b|\b(?:primary|happy|hot|golden|critical|main|sad|unhappy)\s+(?:paths?)\b|\b(?:floor)[^.\n]{0,40}\b(?:ceiling)\b|\b(?:ceiling)[^.\n]{0,40}\b(?:floor)\b/i},
      {"editorializing adjective",
       ~r/\b(?:honest|hacky|clever|neat|nifty|slick|beautiful|ugly|tidy|defensible|defensibly|graceful)\b(?!\s+(?:shutdown|degradation|termination|exit|restart))|\b(?:clean(?:er|est)?|real|true|proper|genuine)\s+(?:code|fix|solution|design|approach|implementation|abstraction|unification|refactor\w*|cleanup|answer|win|interface|separation|option|choice|path|way|method|alternative)s?\b|\b(?:cleaner|cleanest)\b|\b(?:(?:better|simpler|safer|easier|nicer|neater))\s+(?:option|choice|alternative)s?\b/i},
      {"narrative frame", ~r/\b(?:the\s+real\s+need\s+behind)\b/i},
      {"contrast frame", ~r/\b(?:because\s+of)\b[^.\n]{0,80},\s+(?:not\s+because\s+of)\b/i},
      {"contrast frame", ~r/\b(?:is|are|was|were)\s+(?:also)\b[^.\n]{0,80},\s+(?:not)\b/i},
      {"contrast frame",
       ~r/\b(?:is|are|was|were)\s+(?!(?:also)\b)[^.\n,:!?]{1,60},\s+(?:not)\b/i},
      {"template frame",
       ~r/\b(?:is|are|was|were)\s+(?:(?:a|the|our|your|my)\s+)?(?:templates?)\s+(?:for)\b/i},
      {"short-answer label", ~r/\b(?:short|long|quick)\s+(?:answer|version)\b|\bTL;?DR\b/i},
      {"anatomy frame", ~r/\b(?:anatomy)\s+(?:of)\b/i},
      {"dead metaphor",
       ~r/\b(?:is|are|was|were)\s+(?:(?:effectively|basically|practically)\s+)?(?:dead)\b/i},
      {"aphoristic fragment", ~r/\b(?:one)\s+\w+(?:\s+\w+){0,2},\s+(?:one)\s+\w+/i},
      {"lie metaphor",
       ~r/\b(?:is|are|was|were)\s+a\s+(?:lie)\b|\b(?:is|are|was|were)\s+(?:lies)\b/i},
      {"side idiom", ~r/\b(?:on)\s+(?:your|my|our|their|his|her)\s+(?:side)\b/i},
      {"story metaphor", ~r/\b(?:stor(?:y|ies))\b/i},
      {"ground metaphor", ~r/\b(?:grounds?|grounded|grounding)\b(?!\s+(?:truth))/i},
      {"leg metaphor", ~r/\b(?:legs?)\b/i},
      {"comma plus 'then' chain", ~r/,\s+(?:then)\b/i},
      {"trailing contrast after long clause", ~r/(?:^|[.!?]\s+|\n)[^.\n!?]{45,},\s+(?:but)\b/i},
      {"design frame", ~r/\b(?:is|are|was|were)\s+the\s+(?:design)\b/i},
      {"but-so causal chain", ~r/\b(?:But)\b[^.!?\n]{1,120},\s+(?:so)\b/i},
      {"comma plus -ing clause",
       ~r/,\s+(?!everything\b|anything\b|nothing\b|something\b|string\b|thing\b)\w+ing\b/i},
      {"comment narration",
       ~r/\b(?:this\s+(?:ensures|allows|helps|makes\s+sure|guarantees)|note\s+that|note:|important:|make\s+sure\s+(?:to|that))\b/i},
      {"banned word", ~r/\b(?:fails\s+(?:loudly|quietly)|spearheaded|crutch|load\s+bearing)\b/i},
      {"container verb 'carry'", ~r/\b(?:carry|carries|carried|carrying)\b/i},
      {"LLM vocabulary",
       ~r/\b(?:tapestry|streamlines?|streamlined|cutting-edge|game\s+changer|at\s+its\s+core|dive\s+into|let[’']s\s+dive|multifaceted|pivotal|crucial|myriad|plethora|fosters?|meticulous(?:ly)?|a\s+testament\s+to|in\s+today[’']s|fast-paced|ever-evolving|supercharge|state-of-the-art|production-ready|lightning[- ]fast|elevate\s+your|empower(?:s|ing)?|navigate\s+the\s+complexities|unlock\s+the)\b/iu},
      {"chat opener",
       ~r/^\s*(?:[-*+]\s+)?(?:great\s+question|good\s+question|certainly|absolutely|sure\s+thing|sure|of\s+course|looking\s+at\s+your|here[’']s\s+a|here\s+is\s+a|i[’']d\s+be\s+happy\s+to|i\s+would\s+be\s+happy\s+to)\b/iu},
      {"chat closer",
       ~r/\b(?:let\s+me\s+know\s+if|hope\s+(?:this|that)\s+helps|feel\s+free\s+to|happy\s+to\s+help|(?:don[’']t|do\s+not)\s+hesitate\s+to|if\s+you\s+have\s+any\s+questions|if\s+there(?:[’']s|\s+is)\s+anything\s+else|anything\s+else\s+i\s+can)\b/iu},
      {"chat assistant voice",
       ~r/\b(?:as\s+an\s+ai|as\s+a\s+(?:large\s+)?language\s+model|i\s+(?:don[’']t|do\s+not)\s+have\s+access\s+to|i\s+cannot\s+browse|my\s+knowledge\s+cutoff|my\s+training\s+data)\b/iu},
      {"contrast cliche",
       ~r/\bnot\s+(?:just|only|merely|simply)\s+[^.\n]{1,60}?,?\s+but\b|\bit(?:[’']?s|\s+is)\s+not\s+(?:just\s+|about\s+)?[^.\n]{1,40}?[,;]\s+it(?:[’']?s|\s+is)\b|[^\s,:][^,:\n]{0,29},[ \t]+not[ \t]+[^,:\n]{1,30}:(?=\s|$)/iu},
      {"rhetorical question",
       ~r/\bwhy\?\s+because\b|\bthe\s+(?:result|catch|problem|solution|answer|best\s+part|good\s+news|bottom\s+line|difference)\?/i},
      {"list item with a bold label",
       ~r/^\s*(?:[-*+]|\d+[.)])\s+(?:\*\*[^*\n]{1,80}\*\*|__[^_\n]{1,80}__):?(?=\s+[^\s*_])/i},
      {"list item that starts with an emoji",
       ~r/^\s*(?:[-*+]|\d+[.)])\s+[\x{2300}-\x{23FF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1FAFF}]/iu},
      {"dramatic failure verb",
       ~r/\b(?:blows?\s+up|blowing\s+up|blew\s+up|dies?\s+with|died\s+with|falls?\s+over|fell\s+over|chokes?\s+on|choked\s+on|trips?\s+over|tripped\s+over|bites?\s+(?:us|you)|bit\s+us|explodes?|exploded|barfs?)\b/i},
      {"parenthetical aside",
       ~r/\((?:and|but|though|although|plus|as\s+well\s+as|not\s+to\s+mention)\b[^()\n]*\)?/i},
      {"talk about the change under review",
       Regex.compile!(
         "\\b(?:#{any_of(@review_talk)})\\b|(?:^\\s*|[.!?:;]\\s+)\\K(?:previously|formerly|originally)\\b",
         "iu"
       )},
      {"quoted error message",
       Regex.compile!(
         "[\"“](?:(?:#{any_of(@error_openers)})\\b|\\w+Error:|\\w+ is not (?:a function|defined|iterable)\\b)[^\"”\\n]*[\"”]?",
         "u"
       )},
      {"comment that describes the code",
       Regex.compile!("^\\s*(?:#{any_of(@code_narration)})\\b", "i")}
    ]
  end

  defp any_of(words), do: Enum.map_join(words, "|", &Regex.escape/1)

  @doc """
  Returns the shape findings of a block of lines.

  The shape checks read paragraphs and sentences, not single matches. A
  paragraph is a run of consecutive lines with no blank line. Headings,
  tables, and fenced code end a paragraph. A list item starts a new
  paragraph. Inline code and URLs count as one word each.
  """
  @spec shape([line()]) :: [shape_finding()]
  def shape(lines) do
    lines = lines |> Enum.map(&%{&1 | text: shape_text(&1.text)}) |> blank_fences()
    paragraphs = paragraphs(lines)

    mid_phrase_breaks(lines) ++
      Enum.flat_map(paragraphs, &long_sentences/1) ++
      Enum.flat_map(paragraphs, &wall_of_text/1) ++
      uniform_paragraphs(paragraphs) ++
      Enum.flat_map(paragraphs, &uniform_sentences/1)
  end

  defp shape_text(text) do
    text
    |> then(&Regex.replace(~r/`[^`\n]*`/, &1, "code"))
    |> then(&Regex.replace(~r"https?://\S+", &1, "url"))
    |> String.trim()
  end

  # A fence line and the lines inside a fence become blank lines. A
  # blank line ends a paragraph.
  defp blank_fences(lines) do
    {lines, _in_fence} =
      Enum.map_reduce(lines, false, fn line, in_fence ->
        cond do
          line.text =~ ~r/^(?:```|~~~)/ -> {%{line | text: ""}, not in_fence}
          in_fence -> {%{line | text: ""}, in_fence}
          true -> {line, in_fence}
        end
      end)

    lines
  end

  defp break?(text), do: text == "" or String.starts_with?(text, ["#", "|"])

  defp list_item?(text), do: text =~ ~r/^(?:[-*+]|\d+[.)])\s+/

  defp paragraphs(lines) do
    {paragraphs, _previous} =
      Enum.reduce(lines, {[], nil}, fn line, {paragraphs, previous} ->
        cond do
          break?(line.text) ->
            {paragraphs, nil}

          previous == nil or line.line != previous + 1 or list_item?(line.text) ->
            text = Regex.replace(~r/^(?:[-*+]|\d+[.)])\s+/, line.text, "")
            {[[%{line | text: text}] | paragraphs], line.line}

          true ->
            [current | rest] = paragraphs
            {[[line | current] | rest], line.line}
        end
      end)

    paragraphs
    |> Enum.reverse()
    |> Enum.map(&(&1 |> Enum.reverse() |> paragraph()))
  end

  # Each piece is the offset of a line in the joined text. The offset
  # of a sentence start gives the line of the sentence.
  defp paragraph([first | _] = lines) do
    {pieces, text} =
      Enum.reduce(lines, {[], ""}, fn line, {pieces, text} ->
        text = if text == "", do: text, else: text <> " "
        {[{byte_size(text), line.line} | pieces], text <> line.text}
      end)

    ends = Regex.scan(~r/[.!?]+(?:["')\]]+)?(?:\s+|$)/, text, return: :index)
    starts = [0 | Enum.map(ends, fn [{start, length}] -> start + length end)]
    stops = Enum.map(ends, fn [{start, _length}] -> start end) ++ [byte_size(text)]

    sentences =
      for {start, stop} <- Enum.zip(starts, stops),
          words = text |> binary_part(start, stop - start) |> String.split(),
          words != [] do
        {_offset, line} = Enum.find(pieces, fn {offset, _line} -> offset <= start end)
        %{line: line, words: length(words), preview: preview(words)}
      end

    %{
      line: first.line,
      sentences: sentences,
      words: sentences |> Enum.map(& &1.words) |> Enum.sum()
    }
  end

  defp preview(words) when length(words) > 6, do: Enum.join(Enum.take(words, 6), " ") <> "..."
  defp preview(words), do: Enum.join(words, " ")

  defp mid_phrase_breaks(lines) do
    dangling = Regex.compile!("\\b(#{Enum.join(@dangling_words, "|")})\\s*$", "i")

    lines
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [previous, line] ->
      continues? =
        line.line == previous.line + 1 and not break?(previous.text) and
          not break?(line.text) and not list_item?(line.text)

      case continues? && Regex.run(dangling, previous.text) do
        [_ending, word] ->
          [%{line: previous.line, class: "line break in the middle of a phrase", match: word}]

        _no_break ->
          []
      end
    end)
  end

  defp long_sentences(paragraph) do
    for sentence <- paragraph.sentences, sentence.words > @long_sentence_words do
      %{line: sentence.line, class: "long sentence", match: sentence.preview}
    end
  end

  defp wall_of_text(%{sentences: [first | _] = sentences} = paragraph) do
    if paragraph.words > @wall_words or length(sentences) > @wall_sentences do
      [%{line: paragraph.line, class: "wall of text", match: first.preview}]
    else
      []
    end
  end

  defp wall_of_text(_paragraph), do: []

  defp uniform_paragraphs(paragraphs, found \\ [])

  defp uniform_paragraphs([], found), do: Enum.reverse(found)

  defp uniform_paragraphs([first | rest] = paragraphs, found) do
    run = uniform_run(paragraphs, first.words, first.words, [])

    if length(run) >= 3 and Enum.min(run) >= @uniform_paragraph_min_words do
      finding = %{
        line: first.line,
        class: "paragraphs of the same length",
        match: "#{Enum.join(run, ", ")} words"
      }

      uniform_paragraphs(Enum.drop(paragraphs, length(run)), [finding | found])
    else
      uniform_paragraphs(rest, found)
    end
  end

  defp uniform_run([], _low, _high, run), do: Enum.reverse(run)

  defp uniform_run([%{words: words} | rest], low, high, run) do
    low = min(low, words)
    high = max(high, words)

    if run != [] and
         (low < @uniform_paragraph_min_words or high > low * @uniform_paragraph_spread) do
      Enum.reverse(run)
    else
      uniform_run(rest, low, high, [words | run])
    end
  end

  defp uniform_sentences(%{sentences: sentences} = paragraph)
       when length(sentences) >= @uniform_sentence_min_count do
    lengths = Enum.map(sentences, & &1.words)
    mean = paragraph.words / length(lengths)
    deviation = :math.sqrt(Enum.sum(Enum.map(lengths, &((&1 - mean) ** 2))) / length(lengths))

    if mean >= @uniform_sentence_min_words and deviation / mean < @uniform_sentence_variation do
      [
        %{
          line: paragraph.line,
          class: "sentences of the same length",
          match: "#{Enum.join(lengths, ", ")} words"
        }
      ]
    else
      []
    end
  end

  defp uniform_sentences(_paragraph), do: []
end
