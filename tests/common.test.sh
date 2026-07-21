# Tests for scripts/common.sh
. "$(dirname "$0")/lib.sh"

t_title "common.sh: in_herdr returns true when HERDR_ENV=1"
. "$(dirname "$0")/../scripts/common.sh"
t_ok "in_herdr"

t_title "common.sh: ensure_agent_detection copies toml in herdr env"
FAKEHOME=$(make_fake_home)
OLD_HOME="$HOME"
export HOME="$FAKEHOME"
HERDR_PLUGIN_CONFIG_DIR="$FAKEHOME/.config/herdr/plugins/freebuff-integration"
export HERDR_PLUGIN_CONFIG_DIR
mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
ensure_agent_detection
t_file_contains "$HERDR_PLUGIN_CONFIG_DIR/agent-detection/freebuff.toml" "match_cmdline"
# Cleanup
rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"
unset HERDR_PLUGIN_CONFIG_DIR

t_title "common.sh: ensure_agent_detection is no-op outside herdr"
unset HERDR_ENV
result=$(ensure_agent_detection 2>&1)
t_is "" "$result" "no output when outside herdr"
export HERDR_ENV=1

t_title "common.sh: in_herdr returns false when HERDR_ENV unset"
_SAVED="${HERDR_ENV:-}"
unset HERDR_ENV
. "$(dirname "$0")/../scripts/common.sh"
if in_herdr; then
  t_fail "in_herdr should be false outside herdr"
else
  t_pass "in_herdr false outside herdr"
fi
export HERDR_ENV="$_SAVED"
unset _SAVED
