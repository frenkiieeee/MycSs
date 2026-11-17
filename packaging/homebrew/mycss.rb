# Homebrew cask for MycSs. Copy to the tap (frenkiieeee/homebrew-mycss) as
# Casks/mycss.rb. `scripts/release.sh` fills `version` and `sha256`.
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

  depends_on macos: ">= :sequoia"

  app "MycSs.app"

  zap trash: [
    "~/Library/Caches/MycSs",
    "~/Library/Logs/MycSs.log",
    "~/Library/Preferences/com.mycss.lyrics.plist",
  ]

  caveats <<~EOS
    MycSs is not notarized by Apple. If macOS blocks it the first time:
      right click MycSs > Open, or run
      xattr -dr com.apple.quarantine /Applications/MycSs.app
    After an update, macOS may ask again for Accessibility and Full Disk Access.
  EOS
end
