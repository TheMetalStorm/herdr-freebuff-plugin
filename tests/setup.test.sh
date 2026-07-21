# Tests for scripts/setup.sh
. "$(dirname "$0")/lib.sh"

t_title "setup.sh: seeds agent detection and installs wrapper"
FAKEHOME=$(make_fake_home)
OLD_HOME="$HOME"
export HOME="$FAKEHOME"
HERDR_PLUGIN_CONFIG_DIR="$FAKEHOME/.config/herdr/plugins/freebuff-integration"
export HERDR_PLUGIN_CONFIG_DIR
HERDR_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HERDR_PLUGIN_ROOT
mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"

output=$(HERDR_ENV=1 sh "$(dirname "$0")/../scripts/setup.sh" 2>&1)
last_line=$(echo "$output" | tail -1)
t_is "Freebuff <-> Herdr integration ready." "$last_line" "setup final message"
t_file_contains "$HERDR_PLUGIN_CONFIG_DIR/agent-detection/freebuff.toml" "freebuff" "agent detection seeded"

# Check wrapper was installed
wrapper_path="$FAKEHOME/.local/bin/freebuff"
# Verify placeholder was replaced and real path was embedded
if grep -q "__PLUGIN_ROOT__" "$wrapper_path" 2>/dev/null; then
  t_fail "wrapper still contains placeholder __PLUGIN_ROOT__"
else
  t_pass "placeholder was replaced"
fi
t_file_contains "$wrapper_path" "$HERDR_PLUGIN_ROOT" "wrapper embeds plugin root"
[ -x "$wrapper_path" ] && t_pass "wrapper is executable" || t_fail "wrapper should be executable"

rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"
unset HERDR_PLUGIN_CONFIG_DIR HERDR_PLUGIN_ROOT

t_title "setup.sh: --uninstall removes wrapper"
FAKEHOME=$(mktemp -d)
export HOME="$FAKEHOME"
mkdir -p "$FAKEHOME/.local/bin"
echo "stale content" > "$FAKEHOME/.local/bin/freebuff"
HERDR_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HERDR_PLUGIN_ROOT
output=$(HERDR_ENV=1 sh "$(dirname "$0")/../scripts/setup.sh" --uninstall 2>&1)
t_is "Removed $FAKEHOME/.local/bin/freebuff" "$output" "uninstall removes wrapper"
[ ! -f "$FAKEHOME/.local/bin/freebuff" ] && t_pass "wrapper file gone" || t_fail "wrapper should be removed"
rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"
unset HERDR_PLUGIN_ROOT

t_title "setup.sh: --uninstall with no wrapper prints message"
FAKEHOME=$(mktemp -d)
export HOME="$FAKEHOME"
HERDR_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HERDR_PLUGIN_ROOT
output=$(HERDR_ENV=1 sh "$(dirname "$0")/../scripts/setup.sh" --uninstall 2>&1)
t_is "No wrapper found at $FAKEHOME/.local/bin/freebuff" "$output" "uninstall without wrapper reports no-op"
rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"
unset HERDR_PLUGIN_ROOT
