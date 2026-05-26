#!/usr/bin/env bash
# Build sioyek.app on macOS. Works from a fresh clone -- handles submodule
# init, freeglut bypass, qt@5 PATH wiring, mupdf build, sioyek build, and
# macdeployqt bundling.
#
# Required deps (install once):
#   brew install qt@5 freeglut mesa harfbuzz
#
# Usage:
#   ./build_mac.sh               # standard build, produces build/sioyek.app + DMG
#   ./build_mac.sh portable      # portable build (configs read next to binary)
#   ./build_mac.sh nodmg         # skip the macdeployqt -dmg step (faster iteration)
#   ./build_mac.sh install       # like nodmg, then ./install_mac.sh to /Applications
#
# 'install' is the typical iteration loop: edit code, run the script,
# test the new binary in /Applications immediately.

set -e

# --- Bootstrap: ensure deps + submodules + freeglut bypass -------------------

# 1. Brew deps. Warn (don't fail) if missing -- user might have them via a
# different package manager. qt@5 is the hard requirement; the script will
# fail later on qmake if it's actually missing.
for pkg in qt@5 freeglut mesa harfbuzz; do
    if ! brew list "$pkg" &>/dev/null; then
        echo "warning: brew package '$pkg' not installed (brew install $pkg)"
    fi
done

# 2. Put qt@5 binaries on PATH so qmake / macdeployqt resolve.
QT5_PREFIX=$(brew --prefix qt@5 2>/dev/null || true)
if [ -n "$QT5_PREFIX" ] && [ -x "$QT5_PREFIX/bin/qmake" ]; then
    export PATH="$QT5_PREFIX/bin:$PATH"
fi

# 3. mupdf nested submodules. `git clone --recursive` doesn't always recurse
# into mupdf's own submodules (mujs, extract, etc.) reliably; force init if
# any required file is missing.
if [ ! -f mupdf/thirdparty/mujs/mujs.h ] || [ ! -f mupdf/thirdparty/extract/include/extract/extract.h ]; then
    echo "Initializing mupdf nested submodules..."
    git -C mupdf submodule update --init --recursive || true
fi

# 4. Deinit freeglut. mupdf's Makethird hardcodes libmupdf-glut.a which depends
# on freeglut sources that fail to compile on macOS (X11 headers missing).
# HAVE_GLUT=no doesn't actually skip the target. Removing the submodule's
# source tree makes the make dependency unresolvable in a way that mupdf
# tolerates -- no glut output, but mupdf itself builds fine.
if [ -d mupdf/thirdparty/freeglut/src ]; then
    echo "Deiniting freeglut submodule (X11 headers don't exist on macOS)..."
    git -C mupdf submodule deinit -f thirdparty/freeglut 2>/dev/null || true
fi

# -----------------------------------------------------------------------------

#sys_glut_clfags=`pkg-config --cflags glut gl`
#sys_glut_libs=`pkg-config --libs glut gl`
#sys_harfbuzz_clfags=`pkg-config --cflags harfbuzz`
#sys_harfbuzz_libs=`pkg-config --libs harfbuzz`

if [ -z ${MAKE_PARALLEL+x} ]; then export MAKE_PARALLEL=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); else echo "MAKE_PARALLEL defined"; fi
echo "MAKE_PARALLEL set to $MAKE_PARALLEL"

cd mupdf
#make USE_SYSTEM_HARFBUZZ=yes USE_SYSTEM_GLUT=yes SYS_GLUT_CFLAGS="${sys_glut_clfags}" SYS_GLUT_LIBS="${sys_glut_libs}" SYS_HARFBUZZ_CFLAGS="${sys_harfbuzz_clfags}" SYS_HARFBUZZ_LIBS="${sys_harfbuzz_libs}" -j 4
# Build only the libs sioyek links against (libmupdf + thirdparty libs +
# threads helper). The default 'all' target includes libmupdf-glut.a which
# pulls in freeglut sources we deinitialized above. 'libs' skips it.
make -j$MAKE_PARALLEL libs libmupdf-threads
cd ..

if [[ $1 == portable ]]; then
	qmake pdf_viewer_build_config.pro
else
	qmake "CONFIG+=non_portable" pdf_viewer_build_config.pro
fi

make -j$MAKE_PARALLEL

rm -rf build 2> /dev/null
mkdir build
mv sioyek.app build/
cp -r pdf_viewer/shaders build/sioyek.app/Contents/MacOS/shaders

cp pdf_viewer/prefs.config build/sioyek.app/Contents/MacOS/prefs.config
cp pdf_viewer/prefs_user.config build/sioyek.app/Contents/MacOS/prefs_user.config
cp pdf_viewer/keys.config build/sioyek.app/Contents/MacOS/keys.config
cp pdf_viewer/keys_user.config build/sioyek.app/Contents/MacOS/keys_user.config
cp tutorial.pdf build/sioyek.app/Contents/MacOS/tutorial.pdf

# Capture the current PATH
CURRENT_PATH=$(echo $PATH)

# Define the path to the Info.plist file inside the app bundle
INFO_PLIST="resources/Info.plist"

# Add LSEnvironment key with PATH to Info.plist
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$INFO_PLIST" || echo "LSEnvironment already exists"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:PATH string $CURRENT_PATH" "$INFO_PLIST" || /usr/libexec/PlistBuddy -c "Set :LSEnvironment:PATH $CURRENT_PATH" "$INFO_PLIST"

if [[ $1 == nodmg ]] || [[ $1 == install ]]; then
	# Iteration mode: skip the DMG + zip (saves ~30s) -- only embed Qt
	# frameworks and patch the binary's rpath so the bundle is runnable
	# straight from build/sioyek.app.
	macdeployqt build/sioyek.app
else
	macdeployqt build/sioyek.app -dmg
	zip -r sioyek-release-mac.zip build/sioyek.dmg
fi

if [[ $1 == install ]]; then
	# Chain to ./install_mac.sh -- kill running sioyek, drop the cask if
	# present, and copy the freshly-built bundle into /Applications.
	./install_mac.sh
fi
