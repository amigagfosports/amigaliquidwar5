#!/bin/sh
# Liquid War 5 for AmigaOS 3.x (68040), for Cradle's stove_build and the
# rebuild (STOVE= and OUT= set), without autotools:
# 1. gfopenallegro's allegro4 (allegro4.library, liballeg.a) at
#    GFOPENALLEGRO_REF, built on STOVE into WORK/a4: the native Allegro 4
#    SDK configure.ac's ALLEGRO_SDK names (include/allegro.h, lib/liballeg.a).
# 2. src/Makefile, src/Makefile.dep (and src/base.h if missing) from their .in files
#    with the values configure gives an m68k-amigaos cross build against that
#    SDK (no assembler, system snprintf, -lpthread, -lsocket -lm), then the
#    game: make -C src liquidwar.
# 3. liquidwar.dat. The game's data is not compiled: making it needs Allegro
#    4's host dat tool and the host utils (utils/liquidwar*), which link a
#    host Allegro 4. Neither the stoves nor gfopenallegro (a native
#    reimplementation, no dat writer) have one. So it is the liquidwar.dat of
#    the v5.6.7-open8-rc1-test release, made from this tree's data/ (commit
#    c7d116e), checked by SHA-256. LW5_DATA=FILE gives one made elsewhere.
# OUT: LiquidWar5/ (liquidwar, liquidwar.dat, LIBS/allegro4.library, COPYING,
# SHA256SUMS), the same as LiquidWar5-VERSION-68040.tar.gz, and its .sha256.
# Nothing is published from here.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${OUT:?OUT must be set}"
STOVE=${STOVE:-"$HOME/AmiCradle/kitchen/stoves/os32-gcc16"}
[ -x "$STOVE/prefix/bin/m68k-amigaos-gcc" ] || { echo "no m68k-amigaos-gcc in $STOVE/prefix/bin"; exit 2; }
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/liquidwar5-amiga.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
VERSION=5.6.7
GFOPENALLEGRO_REF=c7126220a4410c8c2b17b0c47cb4a6272e9f55a5
DATA_URL=https://github.com/amigagfosports/amigaliquidwar5/releases/download/v5.6.7-open8-rc1-test/LiquidWar5-5.6.7-open8-rc1-test.tar.gz
DATA_ARCHIVE_SHA256=9b6e7912fd93dbc72948d062ba26ef2881b55b2c47beb541b11a7aa4bf343f32
DATA_SHA256=1df8f8a3a1f0a3a22722243b55faf741534e76bc676df84199243b0707cac1b1

# 1. The Allegro 4 SDK
A4=$WORK/gfopenallegro
git init -q "$A4"
git -C "$A4" fetch -q --depth 1 https://github.com/DalsinAI/gfopenallegro.git "$GFOPENALLEGRO_REF"
git -C "$A4" checkout -q --detach FETCH_HEAD
STOVE="$STOVE" OUT="$WORK/a4" sh "$A4/allegro4/build-amiga.sh" > "$OUT/allegro4-output.txt" 2>&1 \
	|| { tail -n 40 "$OUT/allegro4-output.txt"; exit 1; }
SDK=$WORK/sdk
mkdir -p "$SDK/lib"
cp -R "$A4/allegro4/include" "$SDK/include"
cp "$WORK/a4/liballeg.a" "$SDK/lib/"
[ -f "$SDK/include/allegro.h" ] || { echo "no include/allegro.h in gfopenallegro's allegro4"; exit 2; }
echo "allegro4: gfopenallegro $GFOPENALLEGRO_REF ($(wc -c < "$WORK/a4/allegro4.library") bytes allegro4.library)"

# 2. The game
P=$STOVE/prefix
cd "$ROOT/src"
sed -e "s|@CC@|$P/bin/m68k-amigaos-gcc|" -e 's|@prefix@|/|' -e 's|@exec_prefix@|/|' -e 's|@datarootdir@|/|' \
	-e 's|@datadir@|/|' -e 's|@HOST_OPT@|no|' -e 's|@STATIC@|no|' -e 's|@SNPRINTF@|yes|' \
	-e "s|@ALCFLAGS@|-I$SDK/include|" -e "s|@ALLIBS@|-L$SDK/lib -lalleg|" -e 's|@ALLEGRO_CONFIG@||' \
	-e 's|@ASM@|no|' -e 's|@DEBUG@|no|' -e 's|@EFENCE@|no|' -e 's|@PTHREAD@|-lpthread|' \
	-e 's|@PLATFORM_LIBS@|-lsocket -lm|' -e 's|@GP2X@|no|' -e 's|@host@|m68k-unknown-amigaos|' \
	-e 's|@host_cpu@|m68k|' Makefile.in > Makefile
MADE="Makefile Makefile.dep"
[ -f base.h ] || { sed -e "s|@VERSION@|$VERSION|" base.h.in > base.h; MADE="$MADE base.h"; }
cp Makefile.dep.in Makefile.dep
make -j"${JOBS:-4}" liquidwar DATADIR=. GAMEDIR=. \
	CFLAGS="-noixemul -m68040 -fno-delete-null-pointer-checks -Wno-error=unused-value -Wno-error=unused-variable" \
	LDFLAGS="-noixemul -m68040" > "$OUT/build-output.txt" 2>&1 || { tail -n 60 "$OUT/build-output.txt"; exit 1; }
[ "$(od -An -tx1 -N4 liquidwar | tr -d ' \n')" = "000003f3" ] || { echo "liquidwar is not an AmigaOS hunk executable"; exit 2; }
"$P/bin/m68k-amigaos-gcc" --version | head -n 1

# 3. The data
if [ -n "${LW5_DATA:-}" ]; then
	cp "$LW5_DATA" "$WORK/liquidwar.dat"
else
	curl -fsSL --retry 2 --max-time 600 -o "$WORK/data.tar.gz" "$DATA_URL"
	echo "$DATA_ARCHIVE_SHA256  $WORK/data.tar.gz" | sha256sum -c --quiet -
	tar -xzOf "$WORK/data.tar.gz" LiquidWar5-RC1/liquidwar.dat > "$WORK/liquidwar.dat"
fi
echo "$DATA_SHA256  $WORK/liquidwar.dat" | sha256sum -c --quiet - || { echo "liquidwar.dat is not the pinned one ($DATA_SHA256)"; exit 3; }

D=$OUT/LiquidWar5
rm -rf "$D"
mkdir -p "$D/LIBS"
cp liquidwar "$D/"
cp "$WORK/liquidwar.dat" "$D/"
cp "$WORK/a4/allegro4.library" "$D/LIBS/"
cp "$ROOT/COPYING" "$D/"
(cd "$D" && sha256sum liquidwar liquidwar.dat LIBS/allegro4.library > SHA256SUMS)
rm -f liquidwar ./*.o $MADE
A=LiquidWar5-$VERSION-68040.tar.gz
EPOCH=$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)
tar -C "$OUT" --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" -cf - LiquidWar5 | gzip -n -9 > "$OUT/$A"
(cd "$OUT" && sha256sum "$A" > "$A.sha256")
cat "$D/SHA256SUMS"
