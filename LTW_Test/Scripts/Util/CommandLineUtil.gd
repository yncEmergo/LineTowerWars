class_name CommandLineUtil

## Reading the arguments this process was launched with.
##
## One place, because there are now two readers with the same awkward problem:
## Boot asking whether "--server" was passed, and NetworkConfig asking what
## follows "--address". Both have to know the same two things, and neither
## should have to rediscover them.
##
## First: a custom argument must follow a "--" separator, because Godot treats
## an unrecognised argument before it as an ENGINE argument and refuses to
## start. So the real command line is `godot -- --server`, and the part after
## the separator comes back from get_cmdline_user_args(). Plain get_cmdline_args()
## is searched as well, so an argument that reaches the process by some other
## route still works rather than being silently ignored.
##
## Second: both spellings have to be accepted. `--address 10.0.0.5` arrives as
## two entries and `--address=10.0.0.5` as one, and which one somebody types is
## not something to be strict about.
##
## Nothing here is trusted input in the security sense - it is what the operator
## of this machine typed, not what a remote peer sent.


## Whether a bare flag was passed at all. An empty flag is never present, so a
## config field nobody filled in cannot accidentally match everything.
static func has_flag(flag: String) -> bool:
	if flag.is_empty():
		return false

	var prefix: String = flag + "="
	for argument in _arguments():
		if argument == flag || argument.begins_with(prefix):
			return true
	return false


## The value following a key, in either spelling, or fallback when the key is
## absent. A key given with no value after it reads as absent rather than as an
## empty string, since `--address` alone is a typo, not a request for "".
static func value_for(key: String, fallback: String = "") -> String:
	if key.is_empty():
		return fallback

	var prefix: String = key + "="
	var arguments: PackedStringArray = _arguments()
	for index in range(arguments.size()):
		var argument: String = arguments[index]
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
		if argument == key && index + 1 < arguments.size():
			return arguments[index + 1]
	return fallback


## The same key read as a number, or fallback when it is absent or not one.
## A misspelled port is worth a line in the log: silently falling back to the
## configured one looks exactly like the override having worked.
static func int_for(key: String, fallback: int) -> int:
	var raw: String = value_for(key)
	if raw.is_empty():
		return fallback
	if !raw.is_valid_int():
		Log.warn("Command line value is not a number, using the configured one", {
			"key": key,
			"value": raw,
			"using": fallback,
		})
		return fallback
	return raw.to_int()


## User arguments first, so the documented spelling wins when both carry the
## same key.
static func _arguments() -> PackedStringArray:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	arguments.append_array(OS.get_cmdline_args())
	return arguments
