# Stable MycSs, from the latest numbered release.
#
#   brew tap frenkiieeee/mycss https://github.com/frenkiieeee/MycSs
#   brew install --cask frenkiieeee/mycss/mycss
#
# `version` and `sha256` are filled by the release workflow (.github/workflows/release.yml)
# once the disk image exists, so the checksum is always the one of the published file.
cask "mycss" do
  version "0.2.5"
  sha256 "REPLACE_WITH_SHA256_OF_THE_DMG"

  url "https://github.com/frenkiieeee/MycSs/releases/download/v#{version}/MycSs-#{version}.dmg"
  name "MycSs"
  desc "Synced lyrics on the lock screen, plus a notch for music and widgets"
  homepage "https://github.com/frenkiieeee/MycSs"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "frenkiieeee/mycss/mycss@nightly"
  depends_on macos: :sequoia

  app "MycSs.app"

  # Not notarized: without this macOS says the app is damaged on the first open.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "MycSs.app"],
        base:         :appdir,
        must_succeed: false
  end

  uninstall quit: "com.mycss.lyrics"

  zap trash: [
    "~/Library/Application Support/MycSs",
    "~/Library/Caches/MycSs",
    "~/Library/Logs/MycSs.log",
    "~/Library/Preferences/com.mycss.lyrics.plist",
  ]

  caveats <<~EOS
    MycSs is not notarized by Apple. After an update macOS may ask again for
    Accessibility and Full Disk Access.
  EOS
end
