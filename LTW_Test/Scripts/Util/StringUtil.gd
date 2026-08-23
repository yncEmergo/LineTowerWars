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
