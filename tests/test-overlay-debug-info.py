#!/usr/bin/env python3
"""Guard the game-class overlay against losing javassist debug metadata.

ModTheSpire inserts patches by source line and binds named locals. BaseMod's
CustomRewardLoad patch reads the local variable ``i`` of
CardCrawlGame.loadPostCombat. A class recompiled without -g (no
LocalVariableTable, shifted line numbers) makes that patch fail with
"[source error] no such field: i" on arm64.

The overlay therefore ships the unmodified Steam bytecode for CardCrawlGame
plus a single resize hook. This test parses the shipped class file and asserts
that property without needing javap or the game installed.
"""

import os
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASS = os.path.join(
    REPO, "payload/jar/com/megacrit/cardcrawl/core/CardCrawlGame.class"
)


def dropped_classes():
    path = os.path.join(REPO, "overlay-drop.txt")
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            entry = line.strip()
            if entry and not entry.startswith("#"):
                yield os.path.join("payload/jar", entry)


FORBIDDEN = list(dropped_classes())


class Reader:
    def __init__(self, data):
        self.data = data
        self.off = 0

    def u1(self):
        value = self.data[self.off]
        self.off += 1
        return value

    def u2(self):
        value = struct.unpack_from(">H", self.data, self.off)[0]
        self.off += 2
        return value

    def u4(self):
        value = struct.unpack_from(">I", self.data, self.off)[0]
        self.off += 4
        return value

    def take(self, length):
        value = self.data[self.off : self.off + length]
        self.off += length
        return value


def parse_class(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError(f"{path}: not a class file")

    reader = Reader(data)
    reader.take(8)
    pool_count = reader.u2()
    pool = {}
    index = 1
    while index < pool_count:
        tag = reader.u1()
        if tag == 1:
            length = reader.u2()
            pool[index] = ("utf8", reader.take(length).decode("utf-8", "replace"))
        elif tag in (3, 4):
            reader.take(4)
        elif tag in (5, 6):
            reader.take(8)
            index += 1
        elif tag in (7, 8, 16, 19, 20):
            pool[index] = ("class", reader.u2())
        elif tag in (9, 10, 11, 12, 17, 18):
            pool[index] = ("pair", reader.u2(), reader.u2())
        elif tag == 15:
            reader.take(3)
        else:
            raise ValueError(f"{path}: unsupported constant pool tag {tag}")
        index += 1

    def utf8(cp_index):
        entry = pool[cp_index]
        if entry[0] != "utf8":
            raise ValueError(f"constant {cp_index} is not Utf8")
        return entry[1]

    def class_name(cp_index):
        entry = pool[cp_index]
        if entry[0] != "class":
            raise ValueError(f"constant {cp_index} is not a class")
        return utf8(entry[1])

    def method_ref(cp_index):
        entry = pool[cp_index]
        if entry[0] != "pair":
            raise ValueError(f"constant {cp_index} is not a member ref")
        name_and_type = pool[entry[2]]
        return class_name(entry[1]), utf8(name_and_type[1]), utf8(name_and_type[2])

    reader.u2()  # access flags
    reader.u2()  # this class
    reader.u2()  # super class
    for _ in range(reader.u2()):
        reader.u2()

    def skip_attributes(count):
        for _ in range(count):
            reader.u2()
            reader.take(reader.u4())

    for _ in range(reader.u2()):  # fields
        reader.take(6)
        skip_attributes(reader.u2())

    methods = {}
    for _ in range(reader.u2()):
        reader.u2()  # access flags
        name = utf8(reader.u2())
        descriptor = utf8(reader.u2())
        code = b""
        locals_ = []
        for _ in range(reader.u2()):
            attribute_name = utf8(reader.u2())
            length = reader.u4()
            payload = reader.take(length)
            if attribute_name != "Code":
                continue
            code_reader = Reader(payload)
            code_reader.take(4)
            code_length = code_reader.u4()
            code = code_reader.take(code_length)
            for _ in range(code_reader.u2()):  # exception table
                code_reader.take(8)
            for _ in range(code_reader.u2()):  # code attributes
                inner_name = utf8(code_reader.u2())
                inner_length = code_reader.u4()
                inner = code_reader.take(inner_length)
                if inner_name != "LocalVariableTable":
                    continue
                local_reader = Reader(inner)
                for _ in range(local_reader.u2()):
                    local_reader.take(4)  # start_pc, length
                    local_name = utf8(local_reader.u2())
                    local_desc = utf8(local_reader.u2())
                    local_reader.u2()  # slot
                    locals_.append((local_name, local_desc))
        methods[name] = {"descriptor": descriptor, "code": code, "locals": locals_}
    return pool, methods, method_ref


def main():
    errors = []
    for rel in FORBIDDEN:
        if os.path.exists(os.path.join(REPO, rel)):
            errors.append(f"recompiled helper must not be shipped: {rel}")
    if not os.path.exists(CLASS):
        errors.append(f"missing overlay class: {CLASS}")
    if errors:
        print("FAIL: " + "; ".join(errors), file=sys.stderr)
        return 1

    _pool, methods, method_ref = parse_class(CLASS)

    if "loadPostCombat" not in methods:
        errors.append("CardCrawlGame.loadPostCombat(SaveFile) is missing")
    else:
        locals_ = methods["loadPostCombat"]["locals"]
        if not locals_:
            errors.append("loadPostCombat has no LocalVariableTable")
        if not any(name == "i" for name, _desc in locals_):
            errors.append("loadPostCombat lost the local variable i (BaseMod patch target)")

    if "resize" not in methods:
        errors.append("CardCrawlGame.resize(II)V is missing")
    else:
        resize = methods["resize"]
        if len(resize["code"]) < 5:
            errors.append("resize(II)V no longer calls StsDisplay.onWindowResize")
        else:
            refs = []
            for constant, entry in _pool.items():
                if entry[0] == "pair":
                    try:
                        refs.append(method_ref(constant))
                    except ValueError:
                        pass
            hooks = [
                ref
                for ref in refs
                if ref[0] == "com/megacrit/cardcrawl/desktop/StsDisplay"
                and ref[1] == "onWindowResize"
            ]
            if not hooks:
                errors.append("StsDisplay.onWindowResize is not referenced by the overlay")

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("ok: CardCrawlGame overlay keeps javassist debug metadata and the resize hook")
    return 0


if __name__ == "__main__":
    sys.exit(main())
