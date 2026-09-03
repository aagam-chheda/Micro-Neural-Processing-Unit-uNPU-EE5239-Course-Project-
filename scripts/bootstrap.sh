#!/usr/bin/env bash
# Run this from inside the cloned repo root.
set -e
mkdir -p rtl tb model fw constraints syn pnr scripts \
         docs/roles docs/planning/tasks
touch rtl/.gitkeep tb/.gitkeep model/.gitkeep fw/.gitkeep \
      constraints/.gitkeep syn/.gitkeep pnr/.gitkeep scripts/.gitkeep \
      docs/planning/tasks/.gitkeep
echo "Directory structure created."
