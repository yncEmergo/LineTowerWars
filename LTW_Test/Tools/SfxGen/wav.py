# Writes the .wav files. MONO, 16 bit PCM, 44100 Hz, and all three of those
# are deliberate.
#
# MONO because anything in the world is played through an AudioStreamPlayer3D,
# and a stereo stream reaching one of those cannot be panned properly - the
# listener's own left/right is already the answer, so a second channel in the
# file is at best ignored and at worst fights it. UI sounds are 2D and could be
# stereo, but they are the ones a human records by hand anyway.
#
# 16 BIT PCM rather than Ogg because these are one-shots on the hot path. A
# tower firing twenty times a second in a full maze cannot afford a decode, and
# a 0.2 second sound is 17 kB either way. Set compress/mode=0 (PCM) on the
# import of anything that fires per tick; QOA is the importer's default and is
# fine for the rare ones.
#
# Uses the stdlib `wave` module, which is the same bargain IconGen's png.py
# strikes with zlib: stdlib is free, a pip install would end the "needs Python 3
# and nothing else" property that both tools next door have.

import wave


SAMPLE_RATE = 44100


def _to_int16(samples):
    """Floats in -1..1 to signed 16 bit, hard clipped at the rails."""
    out = bytearray()
    for value in samples:
        scaled = int(round(value * 32767.0))
        if scaled > 32767:
            scaled = 32767
        elif scaled < -32768:
            scaled = -32768
        # Little endian, two's complement.
        out += (scaled & 0xFFFF).to_bytes(2, "little")
    return bytes(out)


def encode(samples):
    """The exact bytes a .wav of these samples would hold.

    Separate from write() so --check can compare against a file on disk
    without writing anything, the way IconGen's --check does.
    """
    import io

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(_to_int16(samples))
    return buffer.getvalue()


def write(path, samples):
    with open(path, "wb") as handle:
        handle.write(encode(samples))
