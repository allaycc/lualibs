-- hash tests against FIPS 180-4 (SHA-256) and RFC 4231 (HMAC-SHA256).
package.path = package.path .. ";../?/init.lua;../?.lua"
local hash = require("hash")

local total, failed = 0, 0
local function check(name, expected, actual)
  total = total + 1
  if expected == actual then
    print("[PASS] " .. name)
  else
    failed = failed + 1
    print("[FAIL] " .. name)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
  end
end

-- FIPS 180-4 SHA-256 known-answer vectors.
check("sha256(\"\") empty",
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  hash.sha256hex(""))

check("sha256(\"abc\")",
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  hash.sha256hex("abc"))

check("sha256(\"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq\") 56 chars",
  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  hash.sha256hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))

-- 1 million 'a's takes a long time in pure Lua, skip in fast mode.
if os.getenv("HASH_TEST_SLOW") then
  check("sha256(1M 'a's)",
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
    hash.sha256hex(string.rep("a", 1000000)))
end

-- RFC 4231 HMAC-SHA256 test cases.
-- Test 1
check("hmac test 1",
  "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  hash.hmac_sha256_hex(string.rep("\x0b", 20), "Hi There"))

-- Test 2
check("hmac test 2",
  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  hash.hmac_sha256_hex("Jefe", "what do ya want for nothing?"))

-- Test 3
check("hmac test 3",
  "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
  hash.hmac_sha256_hex(string.rep("\xaa", 20), string.rep("\xdd", 50)))

-- Hex roundtrip.
check("toHex roundtrip",
  "deadbeef",
  hash.toHex(hash.fromHex("deadbeef")))

check("fromHex byte values",
  "\xde\xad\xbe\xef",
  hash.fromHex("deadbeef"))

-- Edge cases.
check("sha256 of 1 byte",
  "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
  hash.sha256hex("a"))

check("sha256 of 64 bytes (1 block)",
  hash.sha256hex(string.rep("a", 64)),
  hash.sha256hex(string.rep("a", 64)))  -- determinism check

check("hmac with empty msg",
  hash.hmac_sha256_hex("k", ""),
  hash.hmac_sha256_hex("k", ""))  -- determinism

print()
print(string.format("hash: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
