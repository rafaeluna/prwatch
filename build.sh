#!/bin/zsh
# ./build.sh           Build build/PRwatch.app
# ./build.sh test      Run the core tests
# ./build.sh install   Build, copy to ~/Applications, link `prwatch` into ~/.local/bin, and launch
# ./build.sh icon      Re-render Bundle/AppIcon.png and Bundle/AppIcon.icns from Bundle/make-icon.swift
set -euo pipefail
cd "${0:A:h}"

if [[ "${1:-}" == "icon" ]]; then
  iconset=$(mktemp -d)/AppIcon.iconset
  mkdir -p $iconset
  swift Bundle/make-icon.swift Bundle/AppIcon.png
  for size in 16 32 128 256 512; do
    sips -z $size $size Bundle/AppIcon.png --out $iconset/icon_${size}x${size}.png > /dev/null
    sips -z $((size * 2)) $((size * 2)) Bundle/AppIcon.png --out $iconset/icon_${size}x${size}@2x.png > /dev/null
  done
  iconutil -c icns $iconset -o Bundle/AppIcon.icns
  echo "Rendered Bundle/AppIcon.icns"
  exit
fi

if [[ "${1:-}" == "test" ]]; then
  # Command Line Tools keep the Swift Testing framework outside the default search paths.
  frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  libraries=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  swift test -Xswiftc -F -Xswiftc $frameworks -Xlinker -F -Xlinker $frameworks \
    -Xlinker -rpath -Xlinker $frameworks -Xlinker -rpath -Xlinker $libraries
  exit
fi

swift build -c release
binaries=$(swift build -c release --show-bin-path)
app=build/PRwatch.app

rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp Bundle/Info.plist $app/Contents/
cp Bundle/AppIcon.icns $app/Contents/Resources/
cp $binaries/PrwatchApp $binaries/prwatch $app/Contents/MacOS/
codesign --force --sign - $app/Contents/MacOS/prwatch
codesign --force --sign - $app
echo "Built $app"

if [[ "${1:-}" == "install" ]]; then
  pkill -x PrwatchApp || true
  mkdir -p ~/Applications ~/.local/bin
  rm -rf ~/Applications/PRwatch.app
  cp -R $app ~/Applications/
  ln -sf ~/Applications/PRwatch.app/Contents/MacOS/prwatch ~/.local/bin/prwatch
  open ~/Applications/PRwatch.app
  echo "Installed ~/Applications/PRwatch.app and ~/.local/bin/prwatch"
fi
