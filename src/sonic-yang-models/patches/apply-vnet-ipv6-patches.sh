#!/bin/bash
# apply-vnet-ipv6-patches.sh
# Applies sonic-vnet IPv6 YANG patches to the installed yang-models on a SONiC device.
# Run as root or with sudo.

set -e

# ── 1. Locate the installed yang-models directory ───────────────────────────
YANG_DIR=$(python3 -c "
import sys, os
# Try sonic_yang_models package path first
try:
    import sonic_yang_models
    p = os.path.join(os.path.dirname(sonic_yang_models.__file__), 'yang-models')
    if os.path.isdir(p): print(p); sys.exit(0)
except ImportError:
    pass
# Fall back to common SONiC install paths
for d in ['/usr/yang-models', '/usr/local/yang-models',
          '/usr/lib/yang-models', '/usr/share/yang-models']:
    if os.path.isfile(os.path.join(d, 'sonic-vnet.yang')): print(d); sys.exit(0)
sys.exit(1)
" 2>/dev/null) || {
    echo "ERROR: Could not locate sonic-vnet.yang. Set YANG_DIR manually." >&2
    exit 1
}

echo "Found yang-models at: $YANG_DIR"

# ── 2. Back up originals ────────────────────────────────────────────────────
cp -v "$YANG_DIR/sonic-vnet.yang"  "$YANG_DIR/sonic-vnet.yang.bak"
cp -v "$YANG_DIR/sonic-types.yang" "$YANG_DIR/sonic-types.yang.bak"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 3. Apply patches ────────────────────────────────────────────────────────
echo "Patching sonic-vnet.yang..."
patch -d "$YANG_DIR" -p1 --no-backup-if-mismatch \
    < "$SCRIPT_DIR/sonic-vnet-ipv6.patch"

echo "Patching sonic-types.yang..."
patch -d "$YANG_DIR" -p1 --no-backup-if-mismatch \
    < "$SCRIPT_DIR/sonic-types-ipv6.patch"

echo ""
echo "Patches applied. Validating..."

# ── 4. Quick validation with sonic-yang ─────────────────────────────────────
python3 - <<'EOF'
import sonic_yang, json, sys

sy = sonic_yang.SonicYang("/usr/yang-models")
try:
    sy.loadYangModel()
    print("  YANG models loaded OK")
except Exception as e:
    print(f"  YANG load FAILED: {e}")
    sys.exit(1)

# Spot-check: validate an IPv6 VNET_ROUTE entry
test_cfg = {
    "VXLAN_TUNNEL": {"vtep1": {"src_ip": "1.2.3.4"}},
    "VNET": {"Vnet1": {"vxlan_tunnel": "vtep1", "vni": "10001"}},
    "VNET_ROUTE": {
        "Vnet1|fc00::/64": {"nexthop": "2001:db8::1", "ifname": "Ethernet0"}
    },
    "VNET_ROUTE_TUNNEL": {
        "Vnet1|2001:db8::/48": {"endpoint": "2001:db8::1"}
    }
}

try:
    sy.loadData(test_cfg)
    sy.validate_data_tree()
    print("  IPv6 VNET_ROUTE / VNET_ROUTE_TUNNEL validation passed")
except Exception as e:
    print(f"  Validation FAILED: {e}")
    sys.exit(1)

print("\nAll checks passed.")
EOF
