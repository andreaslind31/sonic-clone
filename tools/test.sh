#!/bin/sh
# Run the physics regression suite. Set GODOT to point at a specific binary.
# Exits non-zero if any check fails.
exec "${GODOT:-godot}" --headless --audio-driver Dummy \
    res://tests/tests.tscn --quit-after 120000
