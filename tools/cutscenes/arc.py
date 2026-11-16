import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sclib
BS = chr(92)


def arc(name):
    return sclib.B['..' + BS + '..' + BS + 'DATA' + BS + name.replace('/', BS)]


def entries(name):
    return sclib.pak(arc(name))


def unpack(e):
    if len(e) >= 4 and struct.unpack_from('<I', e, 0)[0] == len(e):
        return e
    return sclib.lzw(e[4:])
