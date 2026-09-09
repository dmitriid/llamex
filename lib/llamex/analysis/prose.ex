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
  # does not compile on OTP 28.
  defp patterns do
    [
      {"em dash", ~r/—/u},
      {"semicolon", ~r/;/},
      {"contraction", ~r/\b\w+n[’']t\b/u},
      {"contraction", ~r/\b\w+[’'](?:re|ll|ve|m)\b/u},
      {"contraction", ~r/\b(?i:it|that|there|here|what|who|he|she|one|let)[’']s\b/u},
      {"banned modal", ~r/\b(?:should|would|might|could)\b/},
      {"banned modal 'may'", ~r/\bmay\b/},
      {"present perfect", ~r/\b(?:has|have|had)\s+been\b/},
      {"present perfect", ~r/\b(?:has|have)\s+\w+ed\b/},
      {"word with no fact",
       ~r/\b(?:simply|seamlessly|seamless|robust|powerful|comprehensive|leverages?|leveraged|utilizes?|utilized|elegant(?:ly)?|effortless(?:ly)?|blazing(?:ly)?|stunning|holistic|battle-tested|world-class|game-chang\w+)\b/},
      {"latin abbreviation", ~r/\be\.g\.|\bi\.e\./},
      {"banned phrase", ~r/\bin order to\b|\bprior to\b|\bin the event that\b/},
      {"filler phrase",
       ~r/\bnot only\b|\bload-bearing\b|\bworth noting\b|\bunder the hood\b|\bheavy lifting\b|\blow-hanging fruit\b|\bdeep[- ]dive\b|\bdelves?\b|\bdelved\b|\bat the end of the day\b|\bboils? down to\b|\bthat (?:being )?said\b|\bneedless to say\b|\brest assured\b|\bkeep in mind\b|\ba breeze\b|\bdouble[- ]check\b|\bdrill down\b/},
      {"metaphor verb",
       ~r/\b(?:rescues?|rescued|nudges?|nudged|swallows?|swallowed|attacks?|attacked|fights?|fought|rides?|rode|lands?|landed|(?:wires?|wired)(?:\s+\w+){0,3}\s+up|(?:slips?|slipped|gets?|got)\s+through)\b/},
      {"container verb 'hold'", ~r/\b(?i:holds?|held|holding)\b/},
      {"status verb 'stand'", ~r/\b(?i:stands?|stood|standing)\b(?!-)/},
      {"fact-free adverb",
       ~r/\b(?i:honestly|frankly|candidly|obviously|clearly|genuinely)\b|\b(?i:to be (?:clear|honest|fair))\b/},
      {"process narration",
       ~r/\b(?i:I stop here|I pause here|I wait for your|I proceed|let me|I(?: will)? go ahead|going ahead and|I will|I need to|now I|now we|here we|first,? we|we now)\b/},
      {"stalling phrase", ~r/\b(?i:wait)\s*--|\b(?i:but\s+wait)\b|\b(?i:hold\s+on)\b/},
      {"user validation phrase",
       ~r/\b(?i:the\s+user\s+is\s+(?:right|correct))\b|\b(?i:you\s+(?:are|were)\s+(?:right|correct))\b/},
      {"pattern label frame", ~r/\b(?i:(?:the\s+)?\w+\s+pattern\s+is)\s*:/},
      {"self-blame phrase",
       ~r/\b(?i:(?:that|this|it)\s+(?:is|was)\s+on\s+me)\b|\b(?i:my\s+(?:bad|mistake|fault|error|oversight))\b|\b(?i:I\s+apologi[sz]e|apologies|mea\s+culpa)\b/},
      {"noun metaphor",
       ~r/\b(?i:guardrails?|wrinkles?|north star|silver bullet|footguns?|rabbit hole|red flags?|smell test|landmines?|moving parts?|pain points?|ticking time bomb|knobs?|treadmills?|security holes?|failure chain|safety nets?)\b|\b(?i:gaps?\s+remains?|gaps?\s+remained|one\s+gap|a\s+gap\s+in|the\s+gap\s+in|coverage\s+gaps?|(?:closes?|closed|fills?|filled|plugs?|plugged)\s+(?:the|a|this|that)\s+gaps?)\b|\b(?i:primary|happy|hot|golden|critical|main|sad|unhappy)\s+(?i:paths?)\b|\b(?i:floor)[^.\n]{0,40}\b(?i:ceiling)\b|\b(?i:ceiling)[^.\n]{0,40}\b(?i:floor)\b/},
      {"editorializing adjective",
       ~r/\b(?i:honest|hacky|clever|neat|nifty|slick|beautiful|ugly|tidy|defensible|defensibly|graceful)\b(?!\s+(?i:shutdown|degradation|termination|exit|restart))|\b(?i:clean(?:er|est)?|real|true|proper|genuine)\s+(?i:code|fix|solution|design|approach|implementation|abstraction|unification|refactor\w*|cleanup|answer|win|interface|separation|option|choice|path|way|method|alternative)s?\b|\b(?i:cleaner|cleanest)\b|\b(?i:(?:better|simpler|safer|easier|nicer|neater))\s+(?i:option|choice|alternative)s?\b/},
      {"narrative frame", ~r/\b(?i:the\s+real\s+need\s+behind)\b/},
      {"contrast frame", ~r/\b(?i:because\s+of)\b[^.\n]{0,80},\s+(?i:not\s+because\s+of)\b/},
      {"contrast frame", ~r/\b(?i:is|are|was|were)\s+(?i:also)\b[^.\n]{0,80},\s+(?i:not)\b/},
      {"contrast frame",
       ~r/\b(?i:is|are|was|were)\s+(?!(?i:also)\b)[^.\n,:!?]{1,60},\s+(?i:not)\b/},
      {"template frame",
       ~r/\b(?i:is|are|was|were)\s+(?:(?i:a|the|our|your|my)\s+)?(?i:templates?)\s+(?i:for)\b/},
      {"short-answer label", ~r/\b(?i:short|long|quick)\s+(?i:answer|version)\b|\bTL;?DR\b/},
      {"anatomy frame", ~r/\b(?i:anatomy)\s+(?i:of)\b/},
      {"dead metaphor",
       ~r/\b(?i:is|are|was|were)\s+(?:(?i:effectively|basically|practically)\s+)?(?i:dead)\b/},
      {"aphoristic fragment", ~r/\b(?i:one)\s+\w+(?:\s+\w+){0,2},\s+(?i:one)\s+\w+/},
      {"lie metaphor",
       ~r/\b(?i:is|are|was|were)\s+a\s+(?i:lie)\b|\b(?i:is|are|was|were)\s+(?i:lies)\b/},
      {"side idiom", ~r/\b(?i:on)\s+(?i:your|my|our|their|his|her)\s+(?i:side)\b/},
      {"story metaphor", ~r/\b(?i:stor(?:y|ies))\b/},
      {"ground metaphor", ~r/\b(?i:grounds?|grounded|grounding)\b(?!\s+(?i:truth))/},
      {"leg metaphor", ~r/\b(?i:legs?)\b/},
      {"comma plus 'then' chain", ~r/,\s+(?i:then)\b/},
      {"trailing contrast after long clause", ~r/(?:^|[.!?]\s+|\n)[^.\n!?]{45,},\s+(?i:but)\b/},
      {"design frame", ~r/\b(?i:is|are|was|were)\s+the\s+(?i:design)\b/},
      {"but-so causal chain", ~r/\b(?i:But)\b[^.!?\n]{1,120},\s+(?i:so)\b/},
      {"comma plus -ing clause",
       ~r/,\s+(?!everything\b|anything\b|nothing\b|something\b|string\b|thing\b)\w+ing\b/},
      {"comment narration",
       ~r/\b(?i:this\s+(?:ensures|allows|helps|makes\s+sure|guarantees)|note\s+that|note:|important:|make\s+sure\s+(?:to|that))\b/}
    ]
  end
end
