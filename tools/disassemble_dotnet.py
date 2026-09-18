#!/usr/bin/env python3
"""Small readable IL dumper built on dnfile and dncil."""

import argparse

import dnfile
from dncil.cil.body.reader import read_method_body_from_bytes
from dncil.clr.token import StringToken, Token


def row_name(row) -> str:
    if hasattr(row, "TypeName"):
        namespace = str(getattr(row, "TypeNamespace", ""))
        return f"{namespace}.{row.TypeName}".strip(".")
    if hasattr(row, "Name"):
        owner = ""
        parent = getattr(row, "Class", None)
        if parent is not None and parent.row is not None:
            owner = row_name(parent.row) + "::"
        return owner + str(row.Name)
    return type(row).__name__


def resolve(pe, operand):
    if isinstance(operand, StringToken):
        return repr(str(pe.net.user_strings.get(operand.rid)))
    if isinstance(operand, Token):
        table = pe.net.mdtables.tables.get(operand.table)
        if table is not None and 0 < operand.rid <= len(table.rows):
            return row_name(table.rows[operand.rid - 1])
    if isinstance(operand, list):
        return ", ".join(hex(value) for value in operand)
    return str(operand) if operand is not None else ""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("assembly")
    parser.add_argument("patterns", nargs="*")
    args = parser.parse_args()
    pe = dnfile.dnPE(args.assembly)
    patterns = [item.lower() for item in args.patterns]

    for method in pe.net.mdtables.MethodDef.rows:
        name = str(method.Name)
        if patterns and not any(pattern in name.lower() for pattern in patterns):
            continue
        if not method.Rva:
            continue
        print(f"\n.method {name} // RVA 0x{method.Rva:x}")
        body = read_method_body_from_bytes(pe.get_data(method.Rva))
        for instruction in body.instructions:
            operand = resolve(pe, instruction.operand)
            print(f"  IL_{instruction.offset:04x}: {instruction.opcode.name:<12} {operand}")


if __name__ == "__main__":
    main()
