"""Run the cloned server's actual reading functions without starting a server.

Only selected function definitions are loaded from its AST. No third-party
dependencies, network listener, mDNS advertisement, or real sensor are used.
This is a behavior characterization, not a claim that stale CCT is acceptable.
"""
import ast
import asyncio
import logging
from pathlib import Path
from types import SimpleNamespace


async def main():
    source = Path(__file__).parent / "repos/lunarsensor/lunarsensor.py"
    module = ast.parse(source.read_text())
    selected = [
        node for node in module.body
        if isinstance(node, ast.AsyncFunctionDef)
        and node.name in {"current_lux", "make_cct_response", "read_color_temperature"}
    ]
    namespace = {
        "log": logging.getLogger("assessment"),
        "time": SimpleNamespace(monotonic=lambda: 1000.0),
        "last_lux": None,
        "last_lux_at": None,
        "last_cct": None,
        "MAX_READING_AGE_SECONDS": 30,
    }
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(source), "exec"), namespace)

    async def missing():
        return None

    namespace["read_lux"] = missing
    assert await namespace["current_lux"]() is None
    print("PASS: missing lux does not fabricate a reading")

    namespace.update(last_lux=300.0, last_lux_at=0.0)
    assert await namespace["current_lux"]() is None
    print("PASS: old lux expires after 30 seconds")

    assert await namespace["read_color_temperature"]() is None
    print("CONFIRMED: the shipped colour reader is an unimplemented stub")

    namespace["last_cct"] = 4200.0
    result = await namespace["make_cct_response"]()
    assert result["value"] == 4200.0
    namespace["time"].monotonic = lambda: 999999.0
    assert (await namespace["make_cct_response"]())["value"] == 4200.0
    print("DEFECT REPRODUCED: cached CCT is re-emitted without any age limit")

    async def invalid_lux():
        return float("inf")

    namespace["read_lux"] = invalid_lux
    assert await namespace["current_lux"]() == float("inf")
    print("DEFECT REPRODUCED: non-finite lux is accepted by the reader layer")


if __name__ == "__main__":
    asyncio.run(main())
