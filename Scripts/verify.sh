#!/bin/bash

set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
	echo "usage: $0 <zip_file> <SUPublicEDKey_base64> <edSignature_base64> [app_path]"
	exit 1
fi

zip_file="$1"
public_key_b64="$2"
signature_b64="$3"
app_path="${4:-}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pub_raw="$tmp_dir/pub.key"
sig_raw="$tmp_dir/sig.bin"
verify_c="$tmp_dir/verify.c"
verify_bin="$tmp_dir/verify"

printf '%s' "$public_key_b64" | base64 -d > "$pub_raw"
printf '%s' "$signature_b64" | base64 -d > "$sig_raw"

pub_len="$(wc -c < "$pub_raw" | tr -d ' ')"
sig_len="$(wc -c < "$sig_raw" | tr -d ' ')"
zip_len="$(stat -f%z "$zip_file")"
zip_sha="$(shasum -a 256 "$zip_file" | awk '{print $1}')"
pub_sha="$(shasum -a 256 "$pub_raw" | awk '{print $1}')"
sig_sha="$(shasum -a 256 "$sig_raw" | awk '{print $1}')"
pub_hex="$(xxd -p -c 256 "$pub_raw")"
sig_hex="$(xxd -p -c 256 "$sig_raw")"

echo "zip file:           $zip_file"
echo "zip bytes:          $zip_len"
echo "zip sha256:         $zip_sha"
echo ""
echo "public key bytes:   $pub_len"
echo "public key sha256:  $pub_sha"
echo "public key base64:  $public_key_b64"
echo "public key hex:     $pub_hex"
echo ""
echo "signature bytes:    $sig_len"
echo "signature sha256:   $sig_sha"
echo "signature base64:   $signature_b64"
echo "signature hex head: ${sig_hex:0:32}"
echo "signature hex tail: ${sig_hex: -32}"
echo ""

if [ "$pub_len" != "32" ]; then
	echo "ERROR: public key is not 32 bytes"
	exit 1
fi

if [ "$sig_len" != "64" ]; then
	echo "ERROR: signature is not 64 bytes"
	exit 1
fi

if [ -n "$app_path" ]; then
	app_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
	app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
	app_short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || true)"

	echo "app path:           $app_path"
	echo "app short version:  ${app_short:-<missing>}"
	echo "app build version:  ${app_build:-<missing>}"
	echo "app SUPublicEDKey:  ${app_key:-<missing>}"

	if [ -n "$app_key" ]; then
		if [ "$app_key" = "$public_key_b64" ]; then
			echo "app key match:      YES"
		else
			echo "app key match:      NO"
		fi
	fi

	echo ""
fi

current_sig="$(Shared/Sparkle/bin/sign_update -p "$zip_file" 2>/dev/null || true)"
if [ -n "$current_sig" ]; then
	echo "sign_update -p:     $current_sig"
	if [ "$current_sig" = "$signature_b64" ]; then
		echo "signature match:    YES (appcast signature matches current signing key)"
	else
		echo "signature match:    NO  (appcast signature differs from current signing key)"
	fi
	echo ""
else
	echo "sign_update -p:     <failed>"
	echo ""
fi

cat > "$verify_c" <<'EOF'
#include <sodium.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned char *read_file(const char *path, long *len_out) {
	FILE *f = fopen(path, "rb");
	if (!f) {
		perror(path);
		return NULL;
	}

	if (fseek(f, 0, SEEK_END) != 0) {
		perror("fseek");
		fclose(f);
		return NULL;
	}

	long len = ftell(f);
	if (len < 0) {
		perror("ftell");
		fclose(f);
		return NULL;
	}

	rewind(f);

	unsigned char *buf = malloc((size_t)len);
	if (!buf) {
		perror("malloc");
		fclose(f);
		return NULL;
	}

	size_t n = fread(buf, 1, (size_t)len, f);
	fclose(f);

	if (n != (size_t)len) {
		fprintf(stderr, "short read for %s\n", path);
		free(buf);
		return NULL;
	}

	*len_out = len;
	return buf;
}

int main(int argc, char **argv) {
	if (argc != 4) {
		fprintf(stderr, "usage: verify <pubkey> <sig> <file>\n");
		return 2;
	}

	if (sodium_init() < 0) {
		fprintf(stderr, "failed to initialize libsodium\n");
		return 2;
	}

	long pub_len = 0, sig_len = 0, file_len = 0;
	unsigned char *pub = read_file(argv[1], &pub_len);
	unsigned char *sig = read_file(argv[2], &sig_len);
	unsigned char *file = read_file(argv[3], &file_len);

	if (!pub || !sig || !file) {
		free(pub);
		free(sig);
		free(file);
		return 2;
	}

	if (pub_len != crypto_sign_PUBLICKEYBYTES) {
		fprintf(stderr, "bad public key length: %ld\n", pub_len);
		free(pub);
		free(sig);
		free(file);
		return 2;
	}

	if (sig_len != crypto_sign_BYTES) {
		fprintf(stderr, "bad signature length: %ld\n", sig_len);
		free(pub);
		free(sig);
		free(file);
		return 2;
	}

	int ok = crypto_sign_verify_detached(sig, file, (unsigned long long)file_len, pub);

	free(pub);
	free(sig);
	free(file);

	if (ok == 0) {
		printf("libsodium verify:   VERIFIED\n");
		return 0;
	} else {
		printf("libsodium verify:   INVALID\n");
		return 1;
	}
}
EOF

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libsodium; then
	cc "$verify_c" $(pkg-config --cflags --libs libsodium) -o "$verify_bin"
else
	brew_prefix="$(brew --prefix libsodium)"
	cc "$verify_c" \
		-I"$brew_prefix/include" \
		-L"$brew_prefix/lib" \
		-Wl,-rpath,"$brew_prefix/lib" \
		-lsodium \
		-o "$verify_bin"
fi

"$verify_bin" "$pub_raw" "$sig_raw" "$zip_file"