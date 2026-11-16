## EA IFF-85 chunk tree as used by Origin's RealSpace engine (big-endian sizes).
## Nodes are dictionaries: { id = "FORM:REAL" | "VERT", off, size, children }.
## `off`/`size` describe the payload inside the original buffer.
extends RefCounted

const CONTAINERS := ["FORM", "CAT ", "LIST"]


static func be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


static func parse(buf: PackedByteArray, start := 0, end := -1) -> Array:
	if end < 0:
		end = buf.size()
	var out := []
	var i := start
	while i + 8 <= end:
		var tag := buf.slice(i, i + 4).get_string_from_ascii()
		var size := be32(buf, i + 4)
		if i + 8 + size > buf.size():
			size = buf.size() - i - 8
		if tag in CONTAINERS and size >= 4:
			var form := buf.slice(i + 8, i + 12).get_string_from_ascii()
			out.append({"id": tag + ":" + form, "off": i + 12, "size": size - 4,
				"children": parse(buf, i + 12, i + 8 + size)})
		else:
			out.append({"id": tag, "off": i + 8, "size": size, "children": []})
		i += 8 + size + (size & 1)
	return out


## Finds a node by path, e.g. ["FORM:REAL", "FORM:APPR", "FORM:POLY"].
static func find(nodes: Array, path: Array):
	for n in nodes:
		if n.id == path[0]:
			return n if path.size() == 1 else find(n.children, path.slice(1))
	return null


static func find_all(nodes: Array, id: String) -> Array:
	return nodes.filter(func(n): return n.id == id)


static func data(buf: PackedByteArray, node) -> PackedByteArray:
	return buf.slice(node.off, node.off + node.size)


## Zero-terminated fixed-length string.
static func cstr(buf: PackedByteArray, off: int, maxlen: int) -> String:
	var end := off
	while end < off + maxlen and end < buf.size() and buf[end] != 0:
		end += 1
	return buf.slice(off, end).get_string_from_ascii()
