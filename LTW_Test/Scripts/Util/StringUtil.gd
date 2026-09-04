class_name StringUtil

# Removes all spaces: String.dedent
# To lower case: String.to_lower


static func is_equal_to_any(text: String, compare_to: Array[String]) -> bool:
	for t: String in compare_to:
		if text == t:
			return true
	return false


## A float as short text, without trailing zeroes or a dangling point, so 2.0
## reads as "2" while 0.75 keeps both of its digits.
##
## The guard matters: with no decimals String.num returns no point at all, and
## stripping zeroes off "20" would leave "2".
static func trim_number(value: float, decimals: int = 2) -> String:
	var text: String = String.num(value, decimals)
	if !text.contains("."):
		return text
	return text.rstrip("0").rstrip(".")


## A whole number as short text for a readout with a column to fit into:
## 999, 1.2k, 15.6k, 102k, 903k, 1.2M.
##
## The bands are the user's, and the reason they are not uniform is that a
## reader wants PRECISION where the numbers are small and SHAPE where they are
## large: the difference between 1.2k and 1.6k is worth a digit, the difference
## between 102k and 103k is not.
##
## Under a thousand it is the plain number, because that is what a player
## counts in.
static func compact_number(value: int) -> String:
	var size: int = absi(value)
	if size < 1000:
		return str(value)
	if size < 100000:
		return "%.1fk" % (value / 1000.0)
	if size < 1000000:
		return "%dk" % roundi(value / 1000.0)
	return "%.1fM" % (value / 1000000.0)


## The suffix that turns a whole number into its ordinal: "st", "nd", "rd" or
## "th". Written out rather than the whole word, so a caller keeps the number
## and only asks for the tail.
##
## The teens are the special case and they are the only one: 11, 12 and 13 all
## take "th" however their last digit reads.
static func ordinal_suffix(value: int) -> String:
	var last_two: int = absi(value) % 100
	if last_two >= 11 && last_two <= 13:
		return "th"
	match absi(value) % 10:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


## "a" or "an", whichever fits the word after it. Written out rather than baked
## into each sentence, because the words these sit in front of are unit NAMES
## read out of a .tres - "a Voidalisk", "an Ultimate Harbinger" - and nothing
## authoring one should have to think about the article.
##
## The vowel test and nothing cleverer. English has exceptions in both
## directions ("a unicorn", "an hour") and no name in this game is one; a name
## that ever is needs its article authored rather than guessed.
static func article(word: String) -> String:
	if word.is_empty():
		return "a"
	return "an" if "aeiou".contains(word.to_lower()[0]) else "a"


## A word made plural when there is not exactly one of the thing, so a
## generated line reads "3 Ghouls" and "1 Ghoul" off the same call.
##
## Regular English only - "s", "es" after a sibilant, "y" to "ies" after a
## consonant - which is every name in the roster and every noun any generated
## description uses. A word that does not follow those rules hands its plural
## in as `irregular`, which is what "life" and "lives" needs.
static func plural(word: String, count: int, irregular: String = "") -> String:
	if absi(count) == 1 || word.is_empty():
		return word
	if !irregular.is_empty():
		return irregular

	var lower: String = word.to_lower()
	if lower.ends_with("s") || lower.ends_with("x") || lower.ends_with("z") \
			|| lower.ends_with("ch") || lower.ends_with("sh"):
		return word + "es"
	if lower.ends_with("y") && !"aeiou".contains(lower[lower.length() - 2]):
		return word.left(word.length() - 1) + "ies"
	return word + "s"
