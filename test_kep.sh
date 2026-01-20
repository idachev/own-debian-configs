#!/bin/bash
#
# КЕП (Qualified Electronic Signature) USB Token Test Script
# Tests connectivity and PIN authentication for Bulgarian КЕП tokens
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "  КЕП USB Token Test Script"
echo "============================================"
echo ""

# Check if pkcs11-tool is installed
if ! command -v pkcs11-tool &> /dev/null; then
    echo -e "${RED}Error: pkcs11-tool is not installed${NC}"
    echo "Install it with: sudo apt install opensc"
    exit 1
fi

# Common PKCS#11 library paths for Bulgarian КЕП tokens
# SafeNet/Gemalto libraries first (work better with IDPrime cards)
PKCS11_LIBS=(
    "/usr/lib/libIDPrimePKCS11.so"
    "/usr/lib/libeToken.so"
    "/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"
    "/usr/lib/opensc-pkcs11.so"
    "/usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so"
    "/usr/lib/libeTPkcs11.so"
    "/usr/lib/libbit4ipki.so"
    "/usr/lib/libcvP11.so"
)

# Find available PKCS#11 library
PKCS11_LIB=""
for lib in "${PKCS11_LIBS[@]}"; do
    if [ -f "$lib" ]; then
        PKCS11_LIB="$lib"
        break
    fi
done

# Allow custom library path
if [ -n "$1" ] && [ "$1" != "-p" ]; then
    PKCS11_LIB="$1"
    shift
fi

if [ -z "$PKCS11_LIB" ]; then
    echo -e "${RED}Error: No PKCS#11 library found${NC}"
    echo "Please specify the library path as argument:"
    echo "  $0 /path/to/pkcs11.so"
    echo ""
    echo "Common locations:"
    for lib in "${PKCS11_LIBS[@]}"; do
        echo "  - $lib"
    done
    exit 1
fi

echo -e "Using PKCS#11 library: ${GREEN}$PKCS11_LIB${NC}"
echo ""

# Step 1: List available slots
echo -e "${YELLOW}Step 1: Listing available token slots...${NC}"
echo "----------------------------------------"
if ! pkcs11-tool --module "$PKCS11_LIB" --list-slots 2>/dev/null; then
    echo -e "${RED}Failed to list slots. Is your USB token plugged in?${NC}"
    exit 1
fi
echo ""

# Step 2: Show token info
echo -e "${YELLOW}Step 2: Token information...${NC}"
echo "----------------------------------------"
TOKEN_INFO=$(pkcs11-tool --module "$PKCS11_LIB" -T 2>/dev/null)
echo "$TOKEN_INFO"
echo ""

# Check if token is locked
if echo "$TOKEN_INFO" | grep -qi "user PIN locked"; then
    echo -e "${RED}WARNING: Token is LOCKED due to too many failed PIN attempts!${NC}"
    echo "You need to unlock it using the PUK/Admin PIN or contact your КЕП provider."
    exit 1
fi

# Show PIN requirements
PIN_RANGE=$(echo "$TOKEN_INFO" | grep -i "pin min/max" | awk -F: '{print $2}' | tr -d ' ')
if [ -n "$PIN_RANGE" ]; then
    echo -e "PIN length requirement: ${GREEN}${PIN_RANGE} characters${NC}"
fi
echo ""

# Step 3: Test PIN login
echo -e "${YELLOW}Step 3: Testing PIN authentication...${NC}"
echo "----------------------------------------"

# Get PIN from environment variable MY_PIN, or prompt interactively
if [ -n "$MY_PIN" ]; then
    PIN="$MY_PIN"
    echo "Using PIN from MY_PIN environment variable"
else
    echo -n "Enter your КЕП PIN: "
    read -s PIN
    echo ""
fi

if [ -z "$PIN" ]; then
    echo -e "${RED}Error: PIN cannot be empty${NC}"
    echo "Set MY_PIN environment variable or enter PIN when prompted."
    exit 1
fi

# Remove any trailing whitespace/newlines from PIN
PIN=$(echo -n "$PIN" | tr -d '\r\n')

echo "Attempting to login with PIN..."
# Use --list-objects to test login (--test can cause PIN length issues)
if pkcs11-tool --module "$PKCS11_LIB" --login --pin "$PIN" --list-objects --type cert > /dev/null 2>&1; then
    echo -e "${GREEN}PIN authentication successful!${NC}"
else
    echo -e "${RED}PIN authentication failed!${NC}"
    echo "Please check your PIN and try again."
    echo "WARNING: Too many failed attempts may lock your token!"
    exit 1
fi
echo ""

# Step 4: List certificates
echo -e "${YELLOW}Step 4: Listing certificates on token...${NC}"
echo "----------------------------------------"
pkcs11-tool --module "$PKCS11_LIB" --login --pin "$PIN" --list-objects --type cert 2>/dev/null || echo "No certificates found or error listing"
echo ""

# Step 5: List private keys (just names, not the actual keys)
echo -e "${YELLOW}Step 5: Listing private keys on token...${NC}"
echo "----------------------------------------"
pkcs11-tool --module "$PKCS11_LIB" --login --pin "$PIN" --list-objects --type privkey 2>/dev/null || echo "No private keys found or error listing"
echo ""

echo "============================================"
echo -e "${GREEN}  КЕП Token Test Complete!${NC}"
echo "============================================"
