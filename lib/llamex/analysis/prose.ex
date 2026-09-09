defmodule Llamex.Analysis.Prose do
  @moduledoc """
  Pattern scanner for text that machines write and humans do not.

  The pattern classes come from the ASD-STE100 hook that checks chat
  output. This module applies the same classes to text in source files.
  """

  @type finding :: %{class: String.t(), match: String.t()}

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
  # does not compile on OTP 28. Every pattern has the `i` flag. A banned
  # word at the start of a sentence has a capital letter.
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
       ~r/\b(?:this\s+(?:ensures|allows|helps|makes\s+sure|guarantees)|note\s+that|note:|important:|make\s+sure\s+(?:to|that))\b/i}
    ]
  end
end
